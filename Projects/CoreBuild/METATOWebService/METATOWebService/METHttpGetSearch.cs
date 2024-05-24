using System;
using System.IO;
using System.Net;
using System.Globalization;

namespace METATOWebService
{
    /// <summary>
    /// Callweb services using HttpGet 
    /// Handles four types of search (Name, Asic, Abn and postcode)
    /// </summary>
    abstract class METHttpGetSearch
    {
        // ---------------------------------------------------------------------------------------------
        //  Query string depends on whether using RPC or document style
        // ---------------------------------------------------------------------------------------------
        protected abstract string BuildAbnQueryString(string serviceUrl, string searchText, string history, string guid);

        // ---------------------------------------------------------------------------------------------
        //  Query string depends on whether using RPC or document style
        // ---------------------------------------------------------------------------------------------
        protected abstract string BuildAsicQueryString(string serviceUrl, string searchText, string history, string guid);

        // ---------------------------------------------------------------------------------------------
        //  Query stringdepends on whether using RPC or document style
        // ---------------------------------------------------------------------------------------------
        protected abstract string BuildNameQueryString(string serviceUrl, string searchText, string act, string nsw, string nt, string qld, string tas, string vic, string wa, string sa, string postcode, string legalName, string tradingName, string guid);

        // ---------------------------------------------------------------------------------------------
        //  Query stringdepends on whether using RPC or document style
        // ---------------------------------------------------------------------------------------------
        protected abstract string BuildPostcodeQueryString(string serviceUrl, string postcode, string guid);
        // ---------------------------------------------------------------------------------------------
        //  Search by an Abn
        // ---------------------------------------------------------------------------------------------
        public string AbnSearch(string serviceUrl, string searchText, string history, string guid)
        {
            string QueryString = BuildAbnQueryString(serviceUrl, searchText, history, guid);
            HttpWebRequest WebRequest = null;
            try
            {
                WebRequest = BuildRequest(QueryString);
                return ReadResponse(WebRequest);
            }
            catch
            {
                throw;
            }
            finally
            {
                WebRequest.Abort();
            }
        }
        // ---------------------------------------------------------------------------------------------
        //  Search by an Asic number (ACN)
        // ---------------------------------------------------------------------------------------------
        public string AsicSearch(string serviceUrl, string searchText, string history, string guid)
        {
            string QueryString = BuildAsicQueryString(serviceUrl, searchText, history, guid);
            HttpWebRequest WebRequest;
            try
            {
                WebRequest = BuildRequest(QueryString);
                return ReadResponse(WebRequest);
            }
            catch
            {
                throw;
            }
        }

        // ---------------------------------------------------------------------------------------------
        //  Search by a Name
        // ---------------------------------------------------------------------------------------------
        public string NameSearch(string serviceUrl, string searchText, string act, string nsw, string nt, string qld, string tas, string vic, string wa, string sa, string postcode, string legalName, string tradingName, string guid)
        {
            string QueryString = BuildNameQueryString(serviceUrl, searchText, act, nsw, nt, qld, tas, vic, wa, sa, postcode, legalName, tradingName, guid);
            HttpWebRequest WebRequest;
            try
            {
                WebRequest = BuildRequest(QueryString);
                return ReadResponse(WebRequest);
            }
            catch
            {
                throw;
            }
        }
        // ---------------------------------------------------------------------------------------------
        //  Search by a Postcode
        // ---------------------------------------------------------------------------------------------
        public string PostcodeSearch(string serviceUrl, string postcode, string guid)
        {
            string QueryString = BuildPostcodeQueryString(serviceUrl, postcode, guid);
            HttpWebRequest WebRequest;
            try
            {
                WebRequest = BuildRequest(QueryString);
                return ReadResponse(WebRequest);
            }
            catch
            {
                throw;
            }
        }
        // ---------------------------------------------------------------------------------------------
        //  Set the request header details
        // ---------------------------------------------------------------------------------------------
        private static HttpWebRequest BuildRequest(string queryString)
        {
            HttpWebRequest Request;
            Request = (HttpWebRequest)WebRequest.Create(queryString);
            try
            {
                Request.Timeout = int.Parse("100000", CultureInfo.CurrentCulture);
            }
            catch
            {
                Request.Timeout = 100000;
            }
            Request.ContentType = "text/xml; charset=utf-8";
            Request.Proxy = GetWebProxy();
            Request.Method = "GET";
            return (Request);
        }
        // ---------------------------------------------------------------------------------------------
        //  Set proxy depending on settings in the config file
        // ---------------------------------------------------------------------------------------------
        private static IWebProxy GetWebProxy()
        {
            string ProxySetting = "";
            if (ProxySetting.Length > 0)
            {
                return new WebProxy(ProxySetting);
            }
            else
            {
                return WebRequest.GetSystemWebProxy();
            }
        }
        // ---------------------------------------------------------------------------------------------
        //  Return the response from the request as a string 
        // ---------------------------------------------------------------------------------------------
        private static string ReadResponse(HttpWebRequest webRequest)
        {
            StreamReader Reader;
            HttpWebResponse Response;
            String ResponseContents = "";
            try
            {
                Response = ((HttpWebResponse)(webRequest.GetResponse()));
                Reader = new StreamReader(Response.GetResponseStream());
                ResponseContents = Reader.ReadToEnd();
                Reader.Close();
            }
            catch (ObjectDisposedException)
            {
                throw;
            }
            catch (IOException)
            {
                throw;
            }
            catch (SystemException)
            {
                throw;
            }

            ResponseContents = ResponseContents.Replace("\\\"", "\"");
            return ResponseContents;
        }
    }

}