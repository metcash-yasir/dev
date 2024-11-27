using Newtonsoft.Json;
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;

namespace CB701_KleberCustAddressIntegrationHelper
{
    /// <summary>
    /// Klerber customer address search and validation helper
    /// </summary>
    public class METKleberCustAddressSearchAndvalidationHelper
    {
        private string _accessToken;
        private static readonly HttpClient httpClient = new HttpClient();

        public string AccessToken => _accessToken;

        public async Task<string> GenerateOAuthToken(string clientId, string clientSecret, string tenantId)
        {
            string requestUri = $"https://login.microsoftonline.com/{tenantId}/oauth2/token";
            string scope = $"api://{tenantId}/.default";

            var postData = new StringContent($"client_id={Uri.EscapeDataString(clientId)}&client_secret={Uri.EscapeDataString(clientSecret)}&grant_type=client_credentials&scope={scope}",
                                             Encoding.UTF8,
                                             "application/x-www-form-urlencoded");

            try
            {
                HttpResponseMessage response = await httpClient.PostAsync(requestUri, postData);

                response.EnsureSuccessStatusCode();

                string responseBody = await response.Content.ReadAsStringAsync();
                TokenResponse tokenResponse = JsonConvert.DeserializeObject<TokenResponse>(responseBody);
                _accessToken = tokenResponse.AccessToken;

                return _accessToken;
            }
            catch (HttpRequestException e)
            {
                throw new Exception($"Error fetching token: {e.Message}");
            }
        }

        /// <summary>
        /// Perform post request Async
        /// </summary>
        /// <param name="url">APIM url</param>
        /// <param name="subscriptionKey">APIM subscription key</param>
        /// <param name="jsonBody">Json body of the request</param>
        /// <param name="addressValidation">is this address validation</param>
        /// <returns>response or error message</returns>
        public async Task<string> PerformPostRequestAsync(string url, string subscriptionKey, string jsonBody, bool addressValidation)
        {
            HttpRequestMessage requestMessage = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(jsonBody, Encoding.UTF8, "application/json")
            };
            requestMessage.Headers.Add("Ocp-Apim-Subscription-Key", subscriptionKey);
            requestMessage.Headers.Add("Authorization", $"Bearer {_accessToken}");

            try
            {
                HttpResponseMessage response = await httpClient.SendAsync(requestMessage);

                response.EnsureSuccessStatusCode();

                string responseBody = await response.Content.ReadAsStringAsync();

                if (addressValidation)
                {
                    var formattedResponse = JsonConvert.SerializeObject(JsonConvert.DeserializeObject<AddressValidationResponse>(responseBody), Formatting.Indented);
                    return formattedResponse;
                }

                return responseBody;
            }
            catch (HttpRequestException ex)
            {
                if (ex.InnerException is WebException webEx && webEx.Response is HttpWebResponse errorResponse)
                {
                    string errorContent = await new StreamReader(errorResponse.GetResponseStream()).ReadToEndAsync();
                    throw new Exception($"Error in AIS service call for message {jsonBody} with {errorResponse.StatusCode}, {errorContent}");
                }
                else if (ex.InnerException is WebException webExTimeout &&
                        (webExTimeout.Status == WebExceptionStatus.Timeout || webExTimeout.Status == WebExceptionStatus.ConnectFailure))
                {
                    string serviceName = addressValidation ? "address validation" : "predictive address search";
                    throw new Exception($"Call to {serviceName} service failed for {jsonBody}");
                }
                else if (ex.InnerException == null)
                {
                    // Handle the case where InnerException is null
                    string serviceName = addressValidation ? "address validation" : "predictive address search";
                    throw new Exception($"Call to {serviceName} service failed for: {jsonBody}. {ex.Message}.");
                }
                else
                {
                    // Generic fallback for unexpected errors
                    throw new Exception($"Unexpected error occurred during the AIS service call for {jsonBody}. Error: {ex.Message}");
                }
            }        
        }


        /// <summary>
        /// Perform post request Sync
        /// Synchronous wrapper for X++
        /// </summary>
        /// <param name="url">APIM url</param>
        /// <param name="subscriptionKey">APIM subscription key</param>
        /// <param name="jsonBody">Json body of the request</param>
        /// <param name="addressValidation">is this address validation</param>
        /// <returns>response or error message</returns>
        public string PerformPostRequestSync(string url, string subscriptionKey, string jsonBody, bool addressValidation)
        {
            // Call the async method and wait for the result synchronously
            return PerformPostRequestAsync(url, subscriptionKey, jsonBody, addressValidation).GetAwaiter().GetResult();
        }

        /// <summary>
        /// Token response contract
        /// </summary>
        public class TokenResponse
        {
            [JsonProperty("access_token")]
            public string AccessToken { get; set; }

            [JsonProperty("token_type")]
            public string TokenType { get; set; }

            [JsonProperty("expires_in")]
            public string ExpiresIn { get; set; }
        }

        /// <summary>
        /// WebResponse contract
        /// </summary>
        public class WebResponse
        {
            [JsonProperty("StatusCode")]
            public string StatusCode { get; set; }

            [JsonProperty("token_type")]
            public string utputResponse { get; set; }
        }

        /// <summary>
        /// Address validation response contract
        /// </summary>
        public class AddressValidationResponse
        {
            public DtResponse DtResponse { get; set; }
        }

        /// <summary>
        /// Kleber response contract
        /// </summary>
        public class DtResponse
        {
            public string ErrorMessage { get; set; }

            public string ErrorType { get; set; }

            public string RequestId { get; set; }

            public string ResultCount { get; set; }

            public string ValidAddress { get; set; }
        }
    }
}
