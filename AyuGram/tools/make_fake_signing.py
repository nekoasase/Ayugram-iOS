"""Create self-signed codesigning material for an unsigned CI device build.

rules_apple refuses to build a device target without a provisioning profile,
even when the app is going to be re-signed by Sideloadly. This script makes a
throwaway certificate and a matching development profile for the given bundle
id; the workflow imports the certificate into a temporary keychain.

Nothing here is a real Apple credential. The resulting IPA is only meant to be
re-signed with the user's own Apple ID.
"""
import argparse
import datetime
import pathlib
import plistlib
import subprocess
import uuid


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--team-id", default="AAAAAAAAAA")
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--password", default="ayugram")
    args = parser.parse_args()

    out = pathlib.Path(args.output_dir)
    profiles = out / "profiles"
    certs = out / "certs"
    profiles.mkdir(parents=True, exist_ok=True)
    certs.mkdir(parents=True, exist_ok=True)

    key = out / "key.pem"
    cer = out / "cert.pem"
    der = out / "cert.der"
    p12 = certs / "cert.p12"
    p12_password = out / "p12-password.txt"
    p12_password.write_text(args.password)

    run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key, "-out", cer, "-days", "3650",
        "-subj", "/CN=AyuGram CI")
    run("openssl", "x509", "-in", cer, "-outform", "DER", "-out", der)
    run("openssl", "pkcs12", "-export", "-out", p12, "-inkey", key,
        "-in", cer, "-passout", "pass:" + args.password)

    application_id = args.team_id + "." + args.bundle_id
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    profile = {
        "AppIDName": "AyuGram CI",
        "ApplicationIdentifierPrefix": [args.team_id],
        "CreationDate": now,
        "ExpirationDate": now + datetime.timedelta(days=3650),
        "Platform": ["iOS"],
        "DeveloperCertificates": [der.read_bytes()],
        "Entitlements": {
            "application-identifier": application_id,
            "get-task-allow": True,
            "keychain-access-groups": [args.team_id + ".*"],
            "com.apple.developer.team-identifier": args.team_id,
        },
        "Name": "iOS Team Provisioning Profile: " + args.bundle_id,
        "ProvisionedDevices": [],
        "TeamIdentifier": [args.team_id],
        "TeamName": "AyuGram CI",
        "TimeToLive": 3650,
        "UUID": str(uuid.uuid4()).upper(),
        "Version": 1,
    }

    unsigned = out / "unsigned.mobileprovision"
    unsigned.write_bytes(plistlib.dumps(profile, fmt=plistlib.FMT_BINARY))
    signed = profiles / "Telegram.mobileprovision"
    run("openssl", "smime", "-sign", "-binary", "-nodetach",
        "-in", unsigned, "-out", signed, "-outform", "DER",
        "-signer", cer, "-inkey", key)

    print("fake signing material written to", out)


if __name__ == "__main__":
    main()
