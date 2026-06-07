package app;

import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;

public final class CipherEngine {
    private static final byte[] MAGIC = "CJFX1".getBytes(StandardCharsets.US_ASCII);
    private static final byte[] LEGACY_SALT = "token-crypt:v1:fixed-salt".getBytes(StandardCharsets.UTF_8);

    private static final int SALT_BYTES = 16;
    private static final int ITERATIONS = 300_000;
    private static final int KEY_BITS = 256;
    private static final int GCM_TAG_BITS = 128;
    private static final int GCM_TAG_BYTES = GCM_TAG_BITS / 8;
    private static final int IV_BYTES = 12;

    private static final SecureRandom RNG = new SecureRandom();

    private CipherEngine() {}

    private static SecretKeySpec keyFromToken(String token, byte[] salt) throws Exception {
        char[] password = token.toCharArray();
        byte[] keyBytes = null;
        PBEKeySpec spec = null;

        try {
            spec = new PBEKeySpec(password, salt, ITERATIONS, KEY_BITS);
            SecretKeyFactory f = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256");
            keyBytes = f.generateSecret(spec).getEncoded();
            return new SecretKeySpec(keyBytes, "AES");
        } finally {
            if (spec != null) spec.clearPassword();
            Arrays.fill(password, '\0');
            if (keyBytes != null) Arrays.fill(keyBytes, (byte) 0);
        }
    }

    public static String encrypt(String token, String plaintext) throws Exception {
        byte[] salt = new byte[SALT_BYTES];
        byte[] iv = new byte[IV_BYTES];

        RNG.nextBytes(salt);
        RNG.nextBytes(iv);

        SecretKeySpec key = keyFromToken(token, salt);

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_BITS, iv));

        byte[] pt = plaintext == null ? new byte[0] : plaintext.getBytes(StandardCharsets.UTF_8);
        byte[] ct = cipher.doFinal(pt);

        // output = base64( magic/version || salt || iv || ciphertext+tag )
        ByteBuffer bb = ByteBuffer.allocate(MAGIC.length + salt.length + iv.length + ct.length);
        bb.put(MAGIC);
        bb.put(salt);
        bb.put(iv);
        bb.put(ct);

        return Base64.getEncoder().encodeToString(bb.array());
    }

    public static String decrypt(String token, String tokenText) throws Exception {
        if (tokenText == null || tokenText.isBlank()) {
            throw new IllegalArgumentException("Ciphertext is empty");
        }

        byte[] all = Base64.getDecoder().decode(tokenText.trim());

        if (isCurrentFormat(all)) {
            return decryptCurrent(token, all);
        }

        return decryptLegacy(token, all);
    }

    private static boolean isCurrentFormat(byte[] all) {
        if (all.length < MAGIC.length + SALT_BYTES + IV_BYTES + GCM_TAG_BYTES) return false;

        for (int i = 0; i < MAGIC.length; i++) {
            if (all[i] != MAGIC[i]) return false;
        }

        return true;
    }

    private static String decryptCurrent(String token, byte[] all) throws Exception {
        ByteBuffer bb = ByteBuffer.wrap(all);
        bb.position(MAGIC.length);

        byte[] salt = new byte[SALT_BYTES];
        byte[] iv = new byte[IV_BYTES];
        byte[] ct = new byte[bb.remaining() - SALT_BYTES - IV_BYTES];

        bb.get(salt);
        bb.get(iv);
        bb.get(ct);

        return decryptBytes(token, salt, iv, ct);
    }

    private static String decryptLegacy(String token, byte[] all) throws Exception {
        if (all.length < IV_BYTES + GCM_TAG_BYTES) {
            throw new IllegalArgumentException("Ciphertext too short");
        }

        byte[] iv = new byte[IV_BYTES];
        byte[] ct = new byte[all.length - IV_BYTES];

        System.arraycopy(all, 0, iv, 0, IV_BYTES);
        System.arraycopy(all, IV_BYTES, ct, 0, ct.length);

        return decryptBytes(token, LEGACY_SALT, iv, ct);
    }

    private static String decryptBytes(String token, byte[] salt, byte[] iv, byte[] ct) throws Exception {
        SecretKeySpec key = keyFromToken(token, salt);

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_BITS, iv));

        byte[] pt = cipher.doFinal(ct);
        return new String(pt, StandardCharsets.UTF_8);
    }
}