using System;
using System.Text;

namespace METATOWebService
{
    /// <summary>
    /// Callweb services using HttpGet 
    /// Handles four types of search (Name, Asic, Abn and postcode)   /// </summary>
    class METHttpGetDocumentSearch : METHttpGetSearch
    {
        // -----------------------------------------------------------------------------------------------
        //  Return query string for a search by ABN 
        // -----------------------------------------------------------------------------------------------
        protected override string BuildAbnQueryString(string serviceUrl, string searchText, string history, string guid)
        {
            StringBuilder QueryString = new StringBuilder(serviceUrl);
            QueryString.Append("?");
            QueryString.Append("searchString=" + searchText);
            QueryString.Append("&includeHistoricalDetails=" + history);
            QueryString.Append("&authenticationGuid=" + guid);
            return QueryString.ToString();
        }
        // -----------------------------------------------------------------------------------------------
        //  Return query string for a search by Acn 
        // -----------------------------------------------------------------------------------------------
        protected override string BuildAsicQueryString(string serviceUrl, string searchText, string history, string guid)
        {
            StringBuilder QueryString = new StringBuilder(serviceUrl);
            QueryString.Append("?");
            QueryString.Append("searchString=" + searchText);
            QueryString.Append("&includeHistoricalDetails=" + history);
            QueryString.Append("&authenticationGuid=" + guid);
            return QueryString.ToString();
        }

        // -----------------------------------------------------------------------------------------------
        //  Return query string for a search by Name
        // -----------------------------------------------------------------------------------------------
        protected override string BuildNameQueryString(string serviceUrl, string searchText, string act, string nsw, string nt, string qld, string tas, string vic, string wa, string sa, string postcode, string legalName, string tradingName, string guid)
        {
            StringBuilder QueryString = new StringBuilder(serviceUrl);
            QueryString.Append("?");
            QueryString.Append("authenticationGuid=" + System.Net.WebUtility.UrlEncode(guid));
            QueryString.Append("&Name=" + System.Net.WebUtility.UrlEncode(searchText));
            QueryString.Append("&ACT=" + act);
            QueryString.Append("&NSW=" + nsw);
            QueryString.Append("&NT=" + nt);
            QueryString.Append("&QLD=" + qld);
            QueryString.Append("&TAS=" + tas);
            QueryString.Append("&VIC=" + vic);
            QueryString.Append("&WA=" + wa);
            QueryString.Append("&SA=" + sa);
            QueryString.Append("&postcode=" + postcode);
            QueryString.Append("&legalName=" + legalName);
            QueryString.Append("&tradingName=" + tradingName);
            return QueryString.ToString();
        }
        // -----------------------------------------------------------------------------------------------
        //  Return query string for a search by Acn 
        // -----------------------------------------------------------------------------------------------
        protected override string BuildPostcodeQueryString(string serviceUrl, string postcode, string guid)
        {
            StringBuilder QueryString = new StringBuilder(serviceUrl);
            QueryString.Append("?");
            QueryString.Append("postcode=" + postcode);
            QueryString.Append("&authenticationGuid=" + guid);
            return QueryString.ToString();
        }
    }
}