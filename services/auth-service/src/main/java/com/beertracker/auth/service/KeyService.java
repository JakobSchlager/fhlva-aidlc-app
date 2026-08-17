package com.beertracker.auth.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyFactory;
import java.security.interfaces.RSAPrivateCrtKey;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.RSAPublicKeySpec;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Loads the RSA private key from disk at startup, derives the public key,
 * and produces the JWKS JSON for the well-known endpoint.
 */
@Service
public class KeyService {

    @Value("${app.auth.privateKeyPath}")
    private String privateKeyPath;

    private RSAPrivateKey privateKey;
    private RSAPublicKey publicKey;
    private String jwksJson;

    @PostConstruct
    public void init() throws Exception {
        byte[] keyBytes = loadPemBytes(privateKeyPath);
        KeyFactory kf = KeyFactory.getInstance("RSA");

        PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(keyBytes);
        RSAPrivateCrtKey rsaPrivateCrtKey = (RSAPrivateCrtKey) kf.generatePrivate(keySpec);
        this.privateKey = rsaPrivateCrtKey;

        RSAPublicKeySpec pubKeySpec = new RSAPublicKeySpec(
                rsaPrivateCrtKey.getModulus(),
                rsaPrivateCrtKey.getPublicExponent()
        );
        this.publicKey = (RSAPublicKey) kf.generatePublic(pubKeySpec);
        this.jwksJson = buildJwksJson(this.publicKey);
    }

    public RSAPrivateKey getPrivateKey() {
        return privateKey;
    }

    public RSAPublicKey getPublicKey() {
        return publicKey;
    }

    public String getJwksJson() {
        return jwksJson;
    }

    private byte[] loadPemBytes(String path) throws Exception {
        String pem = Files.readString(Paths.get(path));
        // Strip PEM header/footer and whitespace
        pem = pem
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s+", "");
        return Base64.getDecoder().decode(pem);
    }

    private String buildJwksJson(RSAPublicKey key) throws Exception {
        BigInteger modulus = key.getModulus();
        BigInteger exponent = key.getPublicExponent();

        String n = Base64.getUrlEncoder().withoutPadding()
                .encodeToString(toUnsignedBytes(modulus));
        String e = Base64.getUrlEncoder().withoutPadding()
                .encodeToString(toUnsignedBytes(exponent));

        Map<String, Object> jwk = new LinkedHashMap<>();
        jwk.put("kty", "RSA");
        jwk.put("use", "sig");
        jwk.put("alg", "RS256");
        jwk.put("kid", "auth-service-key-1");
        jwk.put("n", n);
        jwk.put("e", e);

        Map<String, Object> jwks = new LinkedHashMap<>();
        jwks.put("keys", List.of(jwk));

        return new ObjectMapper().writeValueAsString(jwks);
    }

    private byte[] toUnsignedBytes(BigInteger value) {
        byte[] bytes = value.toByteArray();
        // BigInteger.toByteArray() may prepend a 0x00 byte for sign; strip it
        if (bytes[0] == 0 && bytes.length > 1) {
            byte[] stripped = new byte[bytes.length - 1];
            System.arraycopy(bytes, 1, stripped, 0, stripped.length);
            return stripped;
        }
        return bytes;
    }
}
