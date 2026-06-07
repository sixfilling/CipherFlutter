package app;

import javafx.animation.PauseTransition;
import javafx.application.Application;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.image.Image;
import javafx.scene.input.Clipboard;
import javafx.scene.input.ClipboardContent;
import javafx.scene.layout.*;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.util.Duration;

import java.awt.Desktop;
import java.net.URI;
import java.security.SecureRandom;
import java.util.Objects;

public class MainApp extends Application {

    private boolean dark = true;

    private static final String APP_TITLE = "CipherJavaFX™";
    private static final String UUID_V7_URL = "https://www.uuidgenerator.net/version7";
    private static final String GITHUB_URL = "https://github.com/sixfilling";

    @Override
    public void start(Stage stage) {
        try {
            Image icon = new Image(Objects.requireNonNull(getClass().getResourceAsStream("/icon.png")));
            stage.getIcons().add(icon);
        } catch (Exception ignored) {}

        Button menuBtn = new Button("☰");
        menuBtn.setFocusTraversable(false);
        menuBtn.setOnAction(e -> showAboutDialog(stage));

        PasswordField tokenHiddenField = new PasswordField();
        tokenHiddenField.setPromptText("Secret token / password");

        TextField tokenVisibleField = new TextField();
        tokenVisibleField.setPromptText("Secret token / password");
        tokenVisibleField.setVisible(false);
        tokenVisibleField.setManaged(false);

        tokenHiddenField.textProperty().bindBidirectional(tokenVisibleField.textProperty());

        StackPane tokenBox = new StackPane(tokenHiddenField, tokenVisibleField);

        Button setToken = new Button("Set token");
        Button generateTokenBtn = new Button("Generate");
        Button showToken = new Button("Show");
        Button theme = new Button("Light mode");

        showToken.setFocusTraversable(false);
        showToken.setOnAction(e -> {
            boolean showing = tokenVisibleField.isVisible();

            tokenVisibleField.setVisible(!showing);
            tokenVisibleField.setManaged(!showing);

            tokenHiddenField.setVisible(showing);
            tokenHiddenField.setManaged(showing);

            showToken.setText(showing ? "Show" : "Hide");

            if (showing) {
                tokenHiddenField.requestFocus();
                tokenHiddenField.positionCaret(tokenHiddenField.getText().length());
            } else {
                tokenVisibleField.requestFocus();
                tokenVisibleField.positionCaret(tokenVisibleField.getText().length());
            }
        });

        HBox topRow = new HBox(10, menuBtn, new Label("Token:"), tokenBox, setToken, generateTokenBtn, showToken, theme);
        topRow.setPadding(new Insets(10));
        topRow.setAlignment(Pos.CENTER_LEFT);
        HBox.setHgrow(tokenBox, Priority.ALWAYS);

        Label helpText = new Label("You can get a UUID v7 here:");
        helpText.getStyleClass().add("help");

        Hyperlink uuidLink = new Hyperlink(UUID_V7_URL);
        uuidLink.getStyleClass().add("helpLink");
        uuidLink.setOnAction(e -> openUrl(UUID_V7_URL));

        HBox helpRow = new HBox(8, helpText, uuidLink);
        helpRow.setPadding(new Insets(0, 10, 10, 10));
        helpRow.setAlignment(Pos.CENTER_LEFT);

        TextArea input = new TextArea();
        input.setPromptText("Input: plaintext OR ciphertext");
        input.setWrapText(true);

        TextArea output = new TextArea();
        output.setPromptText("Output");
        output.setWrapText(true);
        output.setEditable(false);
        output.setFocusTraversable(true);

        Label status = new Label("Choose mode. Set a secret token. Then type or paste.");
        status.getStyleClass().add("status");

        final String[] activeToken = {""};

        Runnable doSetToken = () -> {
            activeToken[0] = tokenHiddenField.getText().trim();

            if (activeToken[0].isEmpty()) {
                status.setText("Token cleared.");
            } else if (activeToken[0].length() < 16) {
                status.setText("Token set, but it is short. Use Generate for better security.");
            } else {
                status.setText("Token set.");
            }
        };

        setToken.setOnAction(e -> doSetToken.run());
        tokenHiddenField.setOnAction(e -> doSetToken.run());
        tokenVisibleField.setOnAction(e -> doSetToken.run());

        generateTokenBtn.setFocusTraversable(false);
        generateTokenBtn.setOnAction(e -> {
            String generated = createRandomToken();

            tokenHiddenField.setText(generated);
            activeToken[0] = generated;

            status.setText("Generated and set strong token. Store it safely.");

            if (tokenVisibleField.isVisible()) {
                tokenVisibleField.requestFocus();
                tokenVisibleField.selectAll();
            } else {
                tokenHiddenField.requestFocus();
                tokenHiddenField.selectAll();
            }
        });

        ToggleGroup modeGroup = new ToggleGroup();
        ToggleButton modeEncrypt = new ToggleButton("Encrypt mode");
        ToggleButton modeDecrypt = new ToggleButton("Decrypt mode");
        modeEncrypt.setToggleGroup(modeGroup);
        modeDecrypt.setToggleGroup(modeGroup);
        modeEncrypt.setSelected(true);

        CheckBox autoCopyEncrypted = new CheckBox("Auto-copy encrypted output");

        HBox modeRow = new HBox(10, new Label("Mode:"), modeEncrypt, modeDecrypt, autoCopyEncrypted);
        modeRow.setPadding(new Insets(0, 10, 0, 10));
        modeRow.setAlignment(Pos.CENTER_LEFT);

        Runnable doEncrypt = () -> {
            if (activeToken[0].isEmpty()) { status.setText("Set token first."); return; }
            try {
                String encrypted = CipherEngine.encrypt(activeToken[0], input.getText());
                output.setText(encrypted);

                if (autoCopyEncrypted.isSelected()) {
                    ClipboardContent cc = new ClipboardContent();
                    cc.putString(encrypted);
                    Clipboard.getSystemClipboard().setContent(cc);
                    status.setText("Encrypted and copied.");
                } else {
                    status.setText("Encrypted.");
                }
            } catch (Exception ex) {
                output.setText("Error: " + ex.getMessage());
                status.setText("Failed.");
            }
        };

        Runnable doDecrypt = () -> {
            if (activeToken[0].isEmpty()) { status.setText("Set token first."); return; }
            try {
                output.setText(CipherEngine.decrypt(activeToken[0], input.getText()));
                status.setText("Decrypted.");
            } catch (Exception ex) {
                output.setText("Wrong token or bad ciphertext.");
                status.setText("Failed.");
            }
        };

        Runnable runSelectedMode = () -> {
            Toggle selected = modeGroup.getSelectedToggle();
            if (selected == modeDecrypt) doDecrypt.run();
            else doEncrypt.run();
        };

        PauseTransition debounce = new PauseTransition(Duration.millis(300));
        debounce.setOnFinished(e -> runSelectedMode.run());

        input.textProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal == null || newVal.isBlank()) {
                output.clear();
                status.setText("Cleared.");
                debounce.stop();
                return;
            }
            debounce.playFromStart();
        });

        modeGroup.selectedToggleProperty().addListener((obs, o, n) -> {
            String txt = input.getText();
            if (txt != null && !txt.isBlank()) debounce.playFromStart();
        });

        Button pasteIn = new Button("Paste input");
        Button pasteInput = new Button("Paste input");
        Button copyOut = new Button("Copy output");
        Button clear = new Button("Clear");

        copyOut.setDisable(true);

        output.textProperty().addListener((obs, oldVal, newVal) ->
                copyOut.setDisable(newVal == null || newVal.isBlank())
        );

        pasteIn.setOnAction(e -> {
            String text = Clipboard.getSystemClipboard().getString();

            if (text == null || text.isBlank()) {
                status.setText("Clipboard is empty.");
                return;
            }

            input.setText(text);
            status.setText("Pasted input.");
        });

        pasteInput.setOnAction(e -> {
            Clipboard clipboard = Clipboard.getSystemClipboard();

            if (clipboard.hasString()) {
                input.setText(clipboard.getString());
                status.setText("Pasted input.");
            } else {
                status.setText("Clipboard has no text.");
            }
        });

        copyOut.setOnAction(e -> {
            String text = output.getText();

            if (text == null || text.isBlank()) {
                status.setText("No output to copy.");
                return;
            }

            ClipboardContent cc = new ClipboardContent();
            cc.putString(text);
            Clipboard.getSystemClipboard().setContent(cc);
            status.setText("Copied output.");
        });

        clear.setOnAction(e -> {
            input.clear();
            output.clear();
            status.setText("Cleared.");
        });

        HBox buttons = new HBox(10, pasteIn, copyOut, clear);
        buttons.setPadding(new Insets(10));

        VBox io = new VBox(8);
        io.setPadding(new Insets(10));
        VBox.setVgrow(input, Priority.ALWAYS);
        VBox.setVgrow(output, Priority.ALWAYS);
        io.getChildren().addAll(new Label("Input"), input, new Label("Output"), output);

        theme.setOnAction(e -> {
            dark = !dark;
            theme.setText(dark ? "Light mode" : "Dark mode");
            stage.getScene().getStylesheets().setAll(dark ? DARK_CSS : LIGHT_CSS);
        });

        VBox root = new VBox(topRow, helpRow, modeRow, io, buttons, status);

        Scene scene = new Scene(root, 854, 480);
        stage.setMinWidth(854);
        stage.setMinHeight(480);
        // stage.setResizable(false); // uncomment if you want a fixed window size

        stage.setTitle(APP_TITLE);
        stage.setScene(scene);
        stage.show();

        scene.getStylesheets().add(DARK_CSS);
    }

    private void showAboutDialog(Stage owner) {
        Dialog<Void> d = new Dialog<>();
        d.initOwner(owner);
        d.initModality(Modality.WINDOW_MODAL);
        d.setTitle("About");

        DialogPane pane = d.getDialogPane();
        pane.getButtonTypes().add(ButtonType.CLOSE);

        Label text = new Label("Made with ♡ by SixFilling");
        text.getStyleClass().add("aboutText");

        Hyperlink gh = new Hyperlink(GITHUB_URL);
        gh.getStyleClass().add("helpLink");
        gh.setOnAction(e -> openUrl(GITHUB_URL));

        VBox box = new VBox(10, text, gh);
        box.setAlignment(Pos.CENTER);
        box.setPadding(new Insets(18));

        pane.setContent(box);
        pane.getStylesheets().setAll(dark ? DARK_CSS : LIGHT_CSS);

        d.showAndWait();
    }

    private static final SecureRandom TOKEN_RNG = new SecureRandom();

    private static final int GENERATED_TOKEN_LENGTH = 24;

    private static final String TOKEN_LOWER = "abcdefghijklmnopqrstuvwxyz";
    private static final String TOKEN_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    private static final String TOKEN_DIGITS = "0123456789";
    private static final String TOKEN_SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?";

    private static String createRandomToken() {
        if (GENERATED_TOKEN_LENGTH < 4) {
            throw new IllegalStateException("Generated token length must be at least 4");
        }

        String allChars = TOKEN_LOWER + TOKEN_UPPER + TOKEN_DIGITS + TOKEN_SYMBOLS;

        char[] token = new char[GENERATED_TOKEN_LENGTH];
        token[0] = randomChar(TOKEN_LOWER);
        token[1] = randomChar(TOKEN_UPPER);
        token[2] = randomChar(TOKEN_DIGITS);
        token[3] = randomChar(TOKEN_SYMBOLS);

        for (int i = 4; i < token.length; i++) {
            token[i] = randomChar(allChars);
        }

        shuffle(token);
        return new String(token);
    }

    private static char randomChar(String chars) {
        return chars.charAt(TOKEN_RNG.nextInt(chars.length()));
    }

    private static void shuffle(char[] chars) {
        for (int i = chars.length - 1; i > 0; i--) {
            int j = TOKEN_RNG.nextInt(i + 1);

            char temp = chars[i];
            chars[i] = chars[j];
            chars[j] = temp;
        }
    }

    private static void openUrl(String url) {
        try {
            Desktop.getDesktop().browse(new URI(url));
        } catch (Exception ignored) {}
    }

    private static final String DARK_CSS =
            "data:text/css," +
                    ".root{ -fx-base:#1A1A1A; -fx-background:#1A1A1A; -fx-control-inner-background:#333333; }" +
                    ".label{ -fx-text-fill:#e7edf7; }" +
                    ".status{ -fx-text-fill:#a8b3cf; }" +
                    ".help{ -fx-text-fill:#c7d2fe; }" +
                    ".aboutText{ -fx-text-fill:#e7edf7; -fx-font-size:14px; }" +
                    ".hyperlink.helpLink{ -fx-text-fill:#60a5fa; }" +
                    ".text-area, .text-field{ -fx-background-color:#333333; -fx-text-fill:#e7edf7; -fx-prompt-text-fill:#7d8aa6; -fx-highlight-fill:#3b82f6; }";

    private static final String LIGHT_CSS =
            "data:text/css," +
                    ".root{ -fx-base:#f5f7fb; -fx-background:#f5f7fb; -fx-control-inner-background:#ffffff; }" +
                    ".label{ -fx-text-fill:#111827; }" +
                    ".status{ -fx-text-fill:#4b5563; }" +
                    ".help{ -fx-text-fill:#1f2937; }" +
                    ".aboutText{ -fx-text-fill:#111827; -fx-font-size:14px; }" +
                    ".hyperlink.helpLink{ -fx-text-fill:#2563eb; }" +
                    ".text-area, .text-field{ -fx-background-color:#ffffff; -fx-text-fill:#111827; -fx-prompt-text-fill:#6b7280; -fx-highlight-fill:#2563eb; }";

    public static void main(String[] args) {
        launch(args);
    }
}
