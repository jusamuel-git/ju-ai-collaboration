using JuProvider.Lib.Protocol.Rules;

namespace JuProvider.Lib.Protocol.Framing;

public static class Checksum
{
    public static byte[] Compute(ChecksumType type, ReadOnlySpan<byte> data) => type switch
    {
        ChecksumType.None => [],
        ChecksumType.Sum8 => [Sum8(data)],
        ChecksumType.Xor8 => [Xor8(data)],
        ChecksumType.Crc16Modbus => Crc16ModbusLittleEndian(data),
        _ => throw new ArgumentOutOfRangeException(nameof(type))
    };

    public static bool Verify(ChecksumType type, ReadOnlySpan<byte> data, ReadOnlySpan<byte> expected) =>
        Compute(type, data).AsSpan().SequenceEqual(expected);

    private static byte Sum8(ReadOnlySpan<byte> data)
    {
        int s = 0;
        foreach (byte b in data) s += b;
        return (byte)(s & 0xFF);
    }

    private static byte Xor8(ReadOnlySpan<byte> data)
    {
        byte x = 0;
        foreach (byte b in data) x ^= b;
        return x;
    }

    private static byte[] Crc16ModbusLittleEndian(ReadOnlySpan<byte> data)
    {
        ushort crc = 0xFFFF;
        foreach (byte b in data)
        {
            crc ^= b;
            for (int i = 0; i < 8; i++)
            {
                crc = (crc & 1) != 0 ? (ushort)((crc >> 1) ^ 0xA001) : (ushort)(crc >> 1);
            }
        }
        return [(byte)(crc & 0xFF), (byte)(crc >> 8)];
    }
}
