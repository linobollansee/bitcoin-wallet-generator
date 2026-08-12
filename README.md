# Bitcoin Wallet Generator

A PowerShell 5.1 / .NET Framework script that generates a Bitcoin mainnet wallet entirely in software.

> **Educational use only. Do not use this script to generate or manage wallets containing significant funds.**

## Features

The script generates:

* A cryptographically secure 256-bit private key
* A secp256k1 compressed public key
* A Bitcoin mainnet P2PKH address
* A compressed-key WIF private key
* Base58Check-encoded Bitcoin data
* SHA-256 and RIPEMD-160 hashes
* Elliptic-curve point multiplication using secp256k1

The implementation does not rely on a Bitcoin library for key derivation or address generation. The elliptic-curve arithmetic and Bitcoin serialization logic are implemented directly in PowerShell using `.NET BigInteger` and cryptographic primitives.

## Requirements

* Windows
* Windows PowerShell 5.1
* .NET Framework with:

  * `System.Numerics.BigInteger`
  * `System.Security.Cryptography.SHA256`
  * `System.Security.Cryptography.RIPEMD160`

The script is intended for **Bitcoin mainnet**.

## Usage

Save the script as:

```text
bitcoin-wallet-generator.ps1
```

Run it from Windows PowerShell:

```powershell
.\bitcoin-wallet-generator.ps1
```

The script generates a new private key and displays:

```text
PRIVATE KEY (HEX)
PRIVATE KEY (WIF)
COMPRESSED PUBLIC KEY
BITCOIN MAINNET ADDRESS
```

Example output format:

```text
PRIVATE KEY (HEX)
--------------------------------------------
<64 hexadecimal characters>

PRIVATE KEY (WIF)
--------------------------------------------
<Bitcoin WIF>

COMPRESSED PUBLIC KEY
--------------------------------------------
<66 hexadecimal characters>

BITCOIN MAINNET ADDRESS
--------------------------------------------
<Bitcoin mainnet address>
```

The values above are placeholders only. A real execution generates a new random key.

## How It Works

The wallet-generation process is approximately:

```text
Secure random 32 bytes
        │
        ▼
Validate private key
        │
        ▼
Private key × secp256k1 generator
        │
        ▼
Compressed public key
        │
        ├──────────────► WIF
        │
        ▼
     SHA-256
        │
        ▼
    RIPEMD-160
        │
        ▼
Add P2PKH mainnet version byte
        │
        ▼
    Base58Check
        │
        ▼
Bitcoin address
```

### Private Key

A 32-byte value is generated using:

```powershell
[System.Security.Cryptography.RandomNumberGenerator]
```

The resulting integer must satisfy:

```text
1 <= private key < n
```

where `n` is the order of the secp256k1 generator.

### Public Key

The public key is calculated using:

```text
Q = d × G
```

where:

* `d` = private key
* `G` = secp256k1 generator point
* `Q` = public key point

The script serializes the public key in compressed SEC format:

```text
02 + X coordinate
```

when `Y` is even, or:

```text
03 + X coordinate
```

when `Y` is odd.

The resulting compressed public key is 33 bytes.

### Bitcoin Address

The script generates a legacy Bitcoin P2PKH address using:

```text
HASH160 = RIPEMD160(SHA256(compressed public key))
```

For Bitcoin mainnet P2PKH, the version byte is:

```text
00
```

The payload is then Base58Check encoded with a four-byte double-SHA-256 checksum.

### WIF

The private key is encoded as compressed WIF using:

```text
80 + private key + 01
```

followed by a four-byte double-SHA-256 checksum and Base58 encoding.

`80` identifies Bitcoin mainnet private keys, while the trailing `01` indicates that the corresponding public key should be treated as compressed.

## Important Security Warning

**The private key and WIF are secrets.**

Anyone who obtains the private key can potentially spend the Bitcoin controlled by the corresponding address.

Never:

* Share the private key
* Share the WIF
* Put a private key in a screenshot
* Paste a private key into a website
* Store an unencrypted private key in cloud storage
* Commit generated keys to Git
* Use this script as a production wallet
* Use a generated key for significant funds without appropriate security review

The Bitcoin address and public key can generally be shared.

## Educational Purpose

This project is intended to demonstrate the underlying components involved in Bitcoin key and address generation, including:

* Cryptographically secure random-number generation
* secp256k1 elliptic-curve arithmetic
* Modular arithmetic
* Modular inverses
* Scalar multiplication
* Compressed public-key serialization
* SHA-256
* RIPEMD-160
* Base58 encoding
* Base58Check encoding
* Wallet Import Format (WIF)
* Legacy P2PKH address construction

It is **not intended to replace a professionally reviewed Bitcoin wallet implementation**.

## Implementation Notes

The script uses `.NET BigInteger`, which is a **signed little-endian** integer type. Because Bitcoin uses fixed-width big-endian values in several places, the script contains explicit conversion routines to handle:

* Signed versus unsigned integers
* Little-endian versus big-endian representation
* Exactly 32-byte private-key values
* 32-byte elliptic-curve coordinates
* Leading zero bytes

The secp256k1 parameters used by the script are the standard Bitcoin curve parameters.

## Network

This script generates **Bitcoin mainnet** data.

It does not generate testnet addresses.

In particular:

```text
P2PKH version: 0x00
WIF version:   0x80
```

Therefore, the generated address is a legacy Bitcoin mainnet P2PKH address.

## Limitations

This script intentionally has a narrow educational scope.

It does not provide:

* HD wallet support
* BIP-32 derivation
* BIP-39 seed phrases
* BIP-44 account derivation
* SegWit addresses
* Bech32 encoding
* Taproot addresses
* Transaction creation
* Transaction signing
* Bitcoin network communication
* Hardware-wallet integration
* Encrypted wallet storage
* Key backup/recovery mechanisms
* Production-grade memory protection

## License

If no license has been selected for this project, treat the code as **all rights reserved** until an explicit open-source license is added.

## Disclaimer

This software is provided for educational purposes only and without any guarantee of correctness, security, or suitability for handling real Bitcoin.

**Do not use it to generate wallets containing significant funds.**
