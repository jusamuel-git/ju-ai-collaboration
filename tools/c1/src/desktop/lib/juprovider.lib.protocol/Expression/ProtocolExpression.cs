using System.Globalization;
using System.Text;

namespace JuProvider.Lib.Protocol.Expression;

/// <summary>
/// 패킷 표현식 ↔ 바이트 (C1, 과거 lib.protocol 로직 참조 재작성 — 단일 구현).
///
/// 문법: 대괄호 [ ] 만 제어 의미를 가진다.
///  - 이름: [NUL] [STX] [ETX] [TAB] [LF] [CR] [DLE] [ACK] [NAK] [ESC]
///  - 16진 1바이트: [0D], [ff]
///  - 그 외 문자는 ASCII 그대로 ({ } , 공백 포함). ASCII 밖 문자는 오류.
/// 예: S{10,1}[CR][LF], [STX]ABC[00][ETX]
/// ToDisplay 결과는 ToBytes로 되돌리면 같은 바이트가 된다.
/// </summary>
public static class ProtocolExpression
{
    private static readonly Dictionary<string, byte> NameToByte = new(StringComparer.OrdinalIgnoreCase)
    {
        ["NUL"] = 0x00, ["STX"] = 0x02, ["ETX"] = 0x03, ["ACK"] = 0x06, ["TAB"] = 0x09,
        ["LF"] = 0x0A, ["CR"] = 0x0D, ["DLE"] = 0x10, ["NAK"] = 0x15, ["ESC"] = 0x1B
    };

    private static readonly Dictionary<byte, string> ByteToName =
        NameToByte.ToDictionary(p => p.Value, p => p.Key.ToUpperInvariant());

    public static byte[] ToBytes(string? expression)
    {
        string s = expression ?? string.Empty;
        var bytes = new List<byte>(s.Length);

        for (int i = 0; i < s.Length;)
        {
            char c = s[i];

            if (c == '[')
            {
                int end = s.IndexOf(']', i + 1);
                if (end < 0)
                {
                    throw new FormatException($"닫는 ']'가 없습니다. 위치 {i}");
                }

                string token = s[(i + 1)..end].Trim();

                if (NameToByte.TryGetValue(token, out byte named))
                {
                    bytes.Add(named);
                }
                else if (token.Length == 2
                         && byte.TryParse(token, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out byte hex))
                {
                    bytes.Add(hex);
                }
                else
                {
                    throw new FormatException($"알 수 없는 바이트 표현입니다: [{token}] 위치 {i}");
                }

                i = end + 1;
                continue;
            }

            if (c > 0x7F)
            {
                throw new FormatException($"ASCII 범위를 벗어난 문자입니다: '{c}' 위치 {i}");
            }

            bytes.Add((byte)c);
            i++;
        }

        return bytes.ToArray();
    }

    public static string ToDisplay(ReadOnlySpan<byte> data)
    {
        var b = new StringBuilder(data.Length);

        foreach (byte x in data)
        {
            if (ByteToName.TryGetValue(x, out string? name))
            {
                b.Append('[').Append(name).Append(']');
            }
            else if (x >= 0x20 && x <= 0x7E && x != (byte)'[')
            {
                b.Append((char)x);
            }
            else
            {
                // '[' 자체도 [5B]로 표기해야 다시 읽을 때 제어 표현으로 오해되지 않는다.
                b.Append('[').Append(x.ToString("X2", CultureInfo.InvariantCulture)).Append(']');
            }
        }

        return b.ToString();
    }

    public static string Hex(ReadOnlySpan<byte> data)
    {
        var b = new StringBuilder(data.Length * 3);
        for (int i = 0; i < data.Length; i++)
        {
            if (i > 0) b.Append(' ');
            b.Append(data[i].ToString("X2", CultureInfo.InvariantCulture));
        }
        return b.ToString();
    }
}
