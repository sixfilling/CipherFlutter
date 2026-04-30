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

        TextField tokenField = new TextField();
        tokenField.setPromptText("Token (UUIDv7, etc)");

        Button setToken = new Button("Set token");
        Button theme = new Button("Light mode");

        HBox topRow = new HBox(10, menuBtn, new Label("Token:"), tokenField, setToken, theme);
        topRow.setPadding(new Insets(10));
        topRow.setAlignment(Pos.CENTER_LEFT);
        HBox.setHgrow(tokenField, Priority.ALWAYS);

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

        Label status = new Label("Choose mode. Set token. Then just type/paste.");
        status.getStyleClass().add("status");

        final String[] activeToken = {""};

        Runnable doSetToken = () -> {
            activeToken[0] = tokenField.getText().trim();
            status.setText(activeToken[0].isEmpty() ? "Token cleared." : "Token set.");
        };

        setToken.setOnAction(e -> doSetToken.run());
        tokenField.setOnAction(e -> doSetToken.run());

        ToggleGroup modeGroup = new ToggleGroup();
        ToggleButton modeEncrypt = new ToggleButton("Encrypt mode");
        ToggleButton modeDecrypt = new ToggleButton("Decrypt mode");
        modeEncrypt.setToggleGroup(modeGroup);
        modeDecrypt.setToggleGroup(modeGroup);
        modeEncrypt.setSelected(true);

        HBox modeRow = new HBox(10, new Label("Mode:"), modeEncrypt, modeDecrypt);
        modeRow.setPadding(new Insets(0, 10, 0, 10));
        modeRow.setAlignment(Pos.CENTER_LEFT);

        Runnable doEncrypt = () -> {
            if (activeToken[0].isEmpty()) { status.setText("Set token first."); return; }
            try {
                output.setText(CipherEngine.encrypt(activeToken[0], input.getText()));
                status.setText("Encrypted.");
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

        Button copyOut = new Button("Copy output");
        Button clear = new Button("Clear");

        copyOut.setOnAction(e -> {
            ClipboardContent cc = new ClipboardContent();
            cc.putString(output.getText());
            Clipboard.getSystemClipboard().setContent(cc);
            status.setText("Copied output.");
        });

        clear.setOnAction(e -> {
            input.clear();
            output.clear();
            status.setText("Cleared.");
        });

        HBox buttons = new HBox(10, copyOut, clear);
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

        Scene scene = new Scene(root, 720, 760);
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
// Still looking for malware?