using System.Net.Http.Json;
using System.Text.Json;

using JuProvider.Lib.Device.Models;

namespace JuProvider.Lib.Data.Api;

public sealed class JuProviderApiClient : IDisposable
{
    private readonly HttpClient _httpClient;

    private readonly JsonSerializerOptions _jsonOptions =
        new()
        {
            PropertyNameCaseInsensitive = true
        };

    public const string ClientIdHeader = "X-JU-Client-Id";
    public const string ClientKeyHeader = "X-JU-Client-Key";

    /*
     * clientId / clientKey:
     * 서버 관리자 API(/api/admin/clients)에서 발급받은 Client 자격.
     * 동기화 API(/api/core/sync/**)는 이 값이 없으면 401로 거부된다.
     */
    public JuProviderApiClient(
        string baseUrl,
        string? clientId = null,
        string? clientKey = null
    )
    {
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            throw new ArgumentException(
                "Server Base URL is required.",
                nameof(baseUrl)
            );
        }

        string normalizedUrl =
            baseUrl.Trim().TrimEnd('/') + "/";

        _httpClient =
            new HttpClient
            {
                BaseAddress = new Uri(
                    normalizedUrl,
                    UriKind.Absolute
                ),

                Timeout = TimeSpan.FromSeconds(5)
            };

        if (!string.IsNullOrWhiteSpace(clientId)
            && !string.IsNullOrWhiteSpace(clientKey))
        {
            _httpClient.DefaultRequestHeaders.Add(
                ClientIdHeader,
                clientId.Trim()
            );

            _httpClient.DefaultRequestHeaders.Add(
                ClientKeyHeader,
                clientKey.Trim()
            );
        }
    }

    /*
     * Server -> Client
     * 전체 Device 조회
     */
    public async Task<List<DeviceSyncModel>> GetDevicesAsync(
        CancellationToken cancellationToken = default
    )
    {
        using HttpResponseMessage response =
            await _httpClient.GetAsync(
                "api/core/sync/devices",
                cancellationToken
            );

        response.EnsureSuccessStatusCode();

        List<DeviceSyncModel>? devices =
            await response.Content
                .ReadFromJsonAsync<List<DeviceSyncModel>>(
                    _jsonOptions,
                    cancellationToken
                );

        return devices ?? [];
    }

    /*
     * Server -> Client
     * Device 단건 조회
     */
    public async Task<DeviceSyncModel?> GetDeviceAsync(
        string devCd,
        CancellationToken cancellationToken = default
    )
    {
        if (string.IsNullOrWhiteSpace(devCd))
        {
            throw new ArgumentException(
                "DEV_CD is required.",
                nameof(devCd)
            );
        }

        string deviceCode =
            Uri.EscapeDataString(
                devCd.Trim().ToUpperInvariant()
            );

        using HttpResponseMessage response =
            await _httpClient.GetAsync(
                $"api/core/sync/devices/{deviceCode}",
                cancellationToken
            );

        if (response.StatusCode ==
            System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }

        response.EnsureSuccessStatusCode();

        return await response.Content
            .ReadFromJsonAsync<DeviceSyncModel>(
                _jsonOptions,
                cancellationToken
            );
    }

    /*
     * User 로그인 (JU-1c)
     * POST api/auth/login
     *
     * 4xx: 서버가 사용자 인증을 거부 → 응답으로 반환 (예외 아님)
     * 5xx: HttpRequestException (호출 측에서 OFFLINE 판정)
     * 연결 실패·타임아웃: HttpRequestException / TaskCanceledException
     */
    public async Task<UserLoginResponse> LoginAsync(
        string loginId,
        string password,
        CancellationToken cancellationToken = default
    )
    {
        using HttpResponseMessage response =
            await _httpClient.PostAsJsonAsync(
                "api/auth/login",
                new
                {
                    loginId,
                    password
                },
                _jsonOptions,
                cancellationToken
            );

        int statusCode =
            (int)response.StatusCode;

        if (statusCode >= 400 && statusCode < 500)
        {
            return new UserLoginResponse
            {
                StatusCode = statusCode
            };
        }

        response.EnsureSuccessStatusCode();

        ApiEnvelope<UserLoginData>? body =
            await response.Content
                .ReadFromJsonAsync<ApiEnvelope<UserLoginData>>(
                    _jsonOptions,
                    cancellationToken
                );

        return new UserLoginResponse
        {
            StatusCode = statusCode,
            Data = body?.Data
        };
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}