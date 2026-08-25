"""Generate local PKCS#8 RSA keys for Snowflake service integrations."""

from __future__ import annotations

import argparse
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


def generate_key_pair(output_directory: Path, service_name: str) -> None:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    public_key_body = b"".join(public_pem.splitlines()[1:-1])

    prefix = service_name.lower()
    (output_directory / f"{prefix}_rsa_key.p8").write_bytes(private_pem)
    (output_directory / f"{prefix}_rsa_key.pub").write_bytes(public_pem)
    (output_directory / f"{prefix}_snowflake_public_key.txt").write_bytes(
        public_key_body
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-directory", required=True, type=Path)
    args = parser.parse_args()

    output_directory = args.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    generate_key_pair(output_directory, "hightouch")
    generate_key_pair(output_directory, "fivetran")
    print(f"Generated Hightouch and Fivetran RSA key pairs in {output_directory}")
    print("Private keys remain local and .secrets/ is excluded from Git.")


if __name__ == "__main__":
    main()
