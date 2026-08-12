# ============================================================
# BITCOIN WALLET GENERATOR
# Windows PowerShell 5.1 / .NET Framework
#
# Generates:
#   - Secure 256-bit private key
#   - secp256k1 compressed public key
#   - Mainnet P2PKH Bitcoin address
#   - WIF private key
#
# NETWORK: BITCOIN MAINNET
#
# EDUCATIONAL USE ONLY
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


# ============================================================
# HEX -> POSITIVE BIGINTEGER
# ============================================================

function Convert-HexToBigInteger {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Hex
    )

    if (($Hex.Length % 2) -ne 0) {
        throw "Hex string must contain an even number of characters."
    }

    [byte[]]$bytes =
        New-Object byte[] (($Hex.Length / 2) + 1)

    for ($i = 0; $i -lt ($Hex.Length / 2); $i++) {

        $position =
            $Hex.Length - (($i + 1) * 2)

        $bytes[$i] =
            [Convert]::ToByte(
                $Hex.Substring($position, 2),
                16
            )
    }

    # Extra zero byte forces positive BigInteger.
    $bytes[$bytes.Length - 1] = 0

    return New-Object System.Numerics.BigInteger (,$bytes)
}


# ============================================================
# BYTES -> BIGINTEGER
# ============================================================

function Convert-BytesToBigInteger {
    param(
        [byte[]]$Bytes
    )

    [byte[]]$tmp =
        New-Object byte[] ($Bytes.Length + 1)

    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        $tmp[$i] =
            $Bytes[$Bytes.Length - 1 - $i]
    }

    # Force positive.
    $tmp[$Bytes.Length] = 0

    return New-Object System.Numerics.BigInteger (,$tmp)
}


# ============================================================
# BIGINTEGER -> EXACTLY 32 BYTE BIG-ENDIAN
#
# IMPORTANT:
# .NET BigInteger is little-endian and signed.
# ToByteArray() can contain an extra 00 sign byte.
# ============================================================

function Convert-BigIntegerTo32Bytes {
    param(
        [System.Numerics.BigInteger]$Value
    )

    if ($Value -lt 0) {
        throw "Value must be non-negative."
    }

    [byte[]]$raw =
        $Value.ToByteArray()

    # Remove a possible extra sign byte.
    if (
        ($raw.Length -eq 33) -and
        ($raw[32] -eq 0)
    ) {
        [byte[]]$magnitude =
            New-Object byte[] 32

        [Array]::Copy(
            $raw,
            0,
            $magnitude,
            0,
            32
        )

        [Array]::Reverse($magnitude)

        return $magnitude
    }

    if ($raw.Length -gt 32) {
        throw "BigInteger does not fit into 32 bytes."
    }

    [byte[]]$result =
        New-Object byte[] 32

    # raw is little-endian.
    # Copy it into the beginning, then reverse the
    # complete 32-byte buffer to obtain big-endian.
    for ($i = 0; $i -lt $raw.Length; $i++) {
        $result[$i] = $raw[$i]
    }

    [Array]::Reverse($result)

    return $result
}


# ============================================================
# BYTES -> HEX
# ============================================================

function Convert-ToHex {
    param(
        [byte[]]$Bytes
    )

    return (
        $Bytes |
        ForEach-Object {
            $_.ToString("x2")
        }
    ) -join ""
}


# ============================================================
# SECP256K1 PARAMETERS
# ============================================================

# Prime:
#
# p =
# FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F

$Global:P =
    Convert-HexToBigInteger `
        "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F"


# Group order:
#
# n =
# FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

$Global:N =
    Convert-HexToBigInteger `
        "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"


# Generator X

$Global:Gx =
    Convert-HexToBigInteger `
        "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"


# Generator Y

$Global:Gy =
    Convert-HexToBigInteger `
        "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8"


# ============================================================
# MODULO
# ============================================================

function Normalize-Mod {
    param(
        [System.Numerics.BigInteger]$Value,

        [System.Numerics.BigInteger]$Modulus
    )

    $result =
        $Value % $Modulus

    if ($result -lt 0) {
        $result += $Modulus
    }

    return $result
}


# ============================================================
# MODULAR INVERSE
# ============================================================

function Mod-Inverse {
    param(
        [System.Numerics.BigInteger]$A,

        [System.Numerics.BigInteger]$M
    )

    $oldR =
        Normalize-Mod $A $M

    $r =
        $M

    $oldS =
        [System.Numerics.BigInteger]::One

    $s =
        [System.Numerics.BigInteger]::Zero

    while ($r -ne 0) {

        $q =
            $oldR / $r

        $temp =
            $oldR - ($q * $r)

        $oldR =
            $r

        $r =
            $temp

        $temp =
            $oldS - ($q * $s)

        $oldS =
            $s

        $s =
            $temp
    }

    if ($oldR -ne 1) {
        throw "Modular inverse does not exist."
    }

    return Normalize-Mod $oldS $M
}


# ============================================================
# EC POINT
# ============================================================

function New-ECPoint {
    param(
        [System.Numerics.BigInteger]$X,

        [System.Numerics.BigInteger]$Y
    )

    return @{
        X        = $X
        Y        = $Y
        Infinity = $false
    }
}


function New-InfinityPoint {

    return @{
        X        = [System.Numerics.BigInteger]::Zero
        Y        = [System.Numerics.BigInteger]::Zero
        Infinity = $true
    }
}


# ============================================================
# ELLIPTIC CURVE POINT ADDITION
# ============================================================

function Add-ECPoint {
    param(
        [hashtable]$A,

        [hashtable]$B
    )

    if ($A.Infinity) {
        return $B
    }

    if ($B.Infinity) {
        return $A
    }

    $p =
        $Global:P


    # --------------------------------------------------------
    # Same X coordinate
    # --------------------------------------------------------

    if ($A.X -eq $B.X) {

        # A + (-A) = infinity

        if (
            (Normalize-Mod ($A.Y + $B.Y) $p) -eq 0
        ) {
            return New-InfinityPoint
        }


        # ----------------------------------------------------
        # Point doubling
        # ----------------------------------------------------

        $numerator =
            3 * $A.X * $A.X

        $denominator =
            2 * $A.Y

        $inverse =
            Mod-Inverse $denominator $p

        $lambda =
            Normalize-Mod (
                $numerator * $inverse
            ) $p
    }
    else {

        # ----------------------------------------------------
        # Point addition
        # ----------------------------------------------------

        $numerator =
            $B.Y - $A.Y

        $denominator =
            $B.X - $A.X

        $inverse =
            Mod-Inverse $denominator $p

        $lambda =
            Normalize-Mod (
                $numerator * $inverse
            ) $p
    }


    # x3 = lambda² - x1 - x2

    $x3 =
        Normalize-Mod (
            ($lambda * $lambda) -
            $A.X -
            $B.X
        ) $p


    # y3 = lambda(x1 - x3) - y1

    $y3 =
        Normalize-Mod (
            ($lambda * ($A.X - $x3)) -
            $A.Y
        ) $p


    return New-ECPoint $x3 $y3
}


# ============================================================
# SCALAR MULTIPLICATION
# ============================================================

function Multiply-ECPoint {
    param(
        [System.Numerics.BigInteger]$K,

        [hashtable]$Point
    )

    $result =
        New-InfinityPoint

    $addend =
        $Point

    $k =
        $K

    while ($k -gt 0) {

        if (($k % 2) -eq 1) {

            $result =
                Add-ECPoint $result $addend
        }

        $addend =
            Add-ECPoint $addend $addend

        $k =
            $k / 2
    }

    return $result
}


# ============================================================
# SHA256
# ============================================================

function SHA256-Bytes {
    param(
        [byte[]]$Data
    )

    $sha =
        [System.Security.Cryptography.SHA256]::Create()

    try {
        return $sha.ComputeHash($Data)
    }
    finally {
        $sha.Dispose()
    }
}


# ============================================================
# DOUBLE SHA256
# ============================================================

function Double-SHA256 {
    param(
        [byte[]]$Data
    )

    $first =
        SHA256-Bytes $Data

    return SHA256-Bytes $first
}


# ============================================================
# RIPEMD160
# ============================================================

function RIPEMD160-Bytes {
    param(
        [byte[]]$Data
    )

    $ripemd =
        [System.Security.Cryptography.RIPEMD160]::Create()

    try {
        return $ripemd.ComputeHash($Data)
    }
    finally {
        $ripemd.Dispose()
    }
}


# ============================================================
# COMPRESSED PUBLIC KEY
# ============================================================

function Get-CompressedPublicKey {
    param(
        [hashtable]$Point
    )

    if ($Point.Infinity) {
        throw "Cannot serialize point at infinity."
    }

    if (($Point.Y % 2) -eq 0) {

        $prefix =
            [byte]0x02
    }
    else {

        $prefix =
            [byte]0x03
    }


    $xBytes =
        Convert-BigIntegerTo32Bytes $Point.X


    [byte[]]$result =
        New-Object byte[] 33


    $result[0] =
        $prefix


    [Array]::Copy(
        $xBytes,
        0,
        $result,
        1,
        32
    )


    return $result
}


# ============================================================
# BASE58 ALPHABET
# ============================================================

$Global:Base58Alphabet =
    "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


# ============================================================
# BASE58 ENCODING
# ============================================================

function Convert-ToBase58 {
    param(
        [byte[]]$Bytes
    )

    $value =
        Convert-BytesToBigInteger $Bytes

    $characters =
        New-Object System.Collections.Generic.List[string]


    while ($value -gt 0) {

        $remainder =
            $value % 58

        $index =
            [int]$remainder

        $characters.Add(
            $Global:Base58Alphabet[$index].ToString()
        )

        $value =
            $value / 58
    }


    # Preserve leading zero bytes.
    # Each leading zero becomes "1".

    foreach ($byte in $Bytes) {

        if ($byte -eq 0) {
            $characters.Add("1")
        }
        else {
            break
        }
    }


    $characters.Reverse()

    return (
        $characters -join ""
    )
}


# ============================================================
# BASE58CHECK
# ============================================================

function Convert-ToBase58Check {
    param(
        [byte[]]$Payload
    )

    $checksum =
        (Double-SHA256 $Payload)[0..3]


    [byte[]]$combined =
        New-Object byte[] ($Payload.Length + 4)


    [Array]::Copy(
        $Payload,
        0,
        $combined,
        0,
        $Payload.Length
    )


    [Array]::Copy(
        $checksum,
        0,
        $combined,
        $Payload.Length,
        4
    )


    return Convert-ToBase58 $combined
}


# ============================================================
# SECURE PRIVATE KEY GENERATION
# ============================================================

function New-BitcoinPrivateKey {

    Write-Host "Generating secure private key..."

    $rng =
        [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {

        while ($true) {

            # 256 bits = 32 bytes

            [byte[]]$bytes =
                New-Object byte[] 32


            # Cryptographically secure random bytes

            $rng.GetBytes($bytes)


            $key =
                Convert-BytesToBigInteger $bytes


            # Valid secp256k1 private key:
            #
            # 1 <= key < N

            if (
                ($key -ge 1) -and
                ($key -lt $Global:N)
            ) {

                Write-Host "Private key generated."

                return $bytes
            }
        }
    }
    finally {
        $rng.Dispose()
    }
}


# ============================================================
# PRIVATE KEY -> WIF
#
# MAINNET:
# 80 + 32-byte private key + 01
# ============================================================

function Convert-PrivateKeyToWIF {
    param(
        [byte[]]$PrivateKey
    )

    if ($PrivateKey.Length -ne 32) {
        throw "Private key must be exactly 32 bytes."
    }


    [byte[]]$payload =
        New-Object byte[] 34


    # Mainnet version byte
    $payload[0] =
        [byte]0x80


    # Private key

    [Array]::Copy(
        $PrivateKey,
        0,
        $payload,
        1,
        32
    )


    # Compressed public key flag

    $payload[33] =
        [byte]0x01


    return Convert-ToBase58Check $payload
}


# ============================================================
# PRIVATE KEY -> BITCOIN MAINNET P2PKH ADDRESS
# ============================================================

function Get-BitcoinAddress {
    param(
        [byte[]]$PrivateKey
    )

    if ($PrivateKey.Length -ne 32) {
        throw "Private key must be exactly 32 bytes."
    }


    # Convert private key bytes to integer

    $privateNumber =
        Convert-BytesToBigInteger $PrivateKey


    if (
        ($privateNumber -lt 1) -or
        ($privateNumber -ge $Global:N)
    ) {
        throw "Invalid secp256k1 private key."
    }


    # Generator point G

    $G =
        New-ECPoint `
            $Global:Gx `
            $Global:Gy


    # Public point:
    #
    # PublicKey = PrivateKey * G

    $publicPoint =
        Multiply-ECPoint `
            $privateNumber `
            $G


    # Compressed SEC public key

    $publicKey =
        Get-CompressedPublicKey $publicPoint


    # --------------------------------------------------------
    # HASH160
    #
    # RIPEMD160(SHA256(public key))
    # --------------------------------------------------------

    $sha =
        SHA256-Bytes $publicKey


    $hash160 =
        RIPEMD160-Bytes $sha


    # --------------------------------------------------------
    # P2PKH MAINNET
    #
    # Version = 00
    # Hash160 = 20 bytes
    # --------------------------------------------------------

    [byte[]]$payload =
        New-Object byte[] 21


    # Mainnet P2PKH version byte
    $payload[0] =
        [byte]0x00


    [Array]::Copy(
        $hash160,
        0,
        $payload,
        1,
        20
    )


    $address =
        Convert-ToBase58Check $payload


    return @{
        PublicKey = $publicKey
        Address   = $address
    }
}


# ============================================================
# GENERATE WALLET
# ============================================================

Write-Host ""
Write-Host "============================================"
Write-Host "        BITCOIN WALLET GENERATOR"
Write-Host "============================================"
Write-Host ""
Write-Host "NETWORK: BITCOIN MAINNET"
Write-Host ""


# Generate private key

$privateKey =
    New-BitcoinPrivateKey


# Derive public key

Write-Host "Deriving secp256k1 public key..."

$result =
    Get-BitcoinAddress $privateKey


# Generate WIF

Write-Host "Creating WIF..."

$wif =
    Convert-PrivateKeyToWIF $privateKey


# Convert keys to hexadecimal

$privateHex =
    Convert-ToHex $privateKey


$publicHex =
    Convert-ToHex $result.PublicKey


# ============================================================
# DISPLAY WALLET
# ============================================================

Write-Host ""
Write-Host "============================================"
Write-Host "                 WALLET"
Write-Host "============================================"


Write-Host ""
Write-Host "PRIVATE KEY (HEX)"
Write-Host "--------------------------------------------"
Write-Host $privateHex


Write-Host ""
Write-Host "PRIVATE KEY (WIF)"
Write-Host "--------------------------------------------"
Write-Host $wif


Write-Host ""
Write-Host "COMPRESSED PUBLIC KEY"
Write-Host "--------------------------------------------"
Write-Host $publicHex


Write-Host ""
Write-Host "BITCOIN MAINNET ADDRESS"
Write-Host "--------------------------------------------"
Write-Host $result.Address


Write-Host ""
Write-Host "============================================"
Write-Host "                 WARNING"
Write-Host "============================================"
Write-Host ""
Write-Host "The private key controls the Bitcoin address."
Write-Host "Anyone possessing it can potentially spend the BTC."
Write-Host ""
Write-Host "DO NOT:"
Write-Host "  - share the private key"
Write-Host "  - share the WIF"
Write-Host "  - put the key in screenshots"
Write-Host "  - paste the key into websites"
Write-Host "  - use this educational script for significant funds"
Write-Host ""
Write-Host "The address itself is safe to share."
Write-Host ""
