using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Xml;

namespace METATOWebService
{
    public class METWebService
    {   
        private bool    _error;
        private string  _serviceUrl;
        private string  _authenticationId;
        private string  _exception;
        private string  _abnStatus;
        private string  _entityType;
        private string  _entityName;

        /// <summary>
        /// Returns true if there is an exception dserviceUring service call.
        /// </summary>
        /// <returns>True, if error occurred; otherwisem false.</returns>
        public bool isError()
        {
            return _error;
        }

        /// <summary>
        /// Gets exception.
        /// </summary>
        /// <returns>Exception</returns>
        public string getException()
        {
            return _exception;
        }

        /// <summary>
        /// Gets ABN status from the service.
        /// </summary>
        /// <returns>ABN status.</returns>
        public string getABNStatus()
        {
            return _abnStatus;
        }

        /// <summary>
        /// Gets entity type.
        /// </summary>
        /// <returns>Entity type.</returns>
        public string getEntityType()
        {
            return _entityType;
        }

        /// <summary>
        /// Gets entity name.
        /// </summary>
        /// <returns>Entity name.</returns>
        public string getEntityName()
        {
            return _entityName;
        }

        /// <summary>
        /// Initializes the <c>METWebService</c> object.
        /// </summary>
        /// <param name="authenticationId">Authentication Id.</param>
        public METWebService(string serviceUrl, string authenticationId)
        {
            _serviceUrl = serviceUrl;
            _authenticationId = authenticationId;
        }

        /// <summary>
        /// Calls service to fetch data from ATO.
        /// </summary>
        /// <param name="abn">Search text.</param>
        public void callService(String searchText)
        {
            try
            {
                METHttpGetDocumentSearch search = new METHttpGetDocumentSearch();
                string response = search.AbnSearch(_serviceUrl, searchText, "N", _authenticationId);
                
                XmlDocument xmlDoc = new XmlDocument();
                xmlDoc.LoadXml(response);

                XmlNodeList exceptionNode = xmlDoc.GetElementsByTagName("exception");

                if (exceptionNode.Count > 0)
                {
                    XmlNodeList exceptionDescription = xmlDoc.GetElementsByTagName("exceptionDescription");
                    string exception = (exceptionDescription != null && exceptionDescription.Count > 0) ? exceptionDescription[0].InnerText : "";
                    throw new Exception(exception);
                }

                XmlNodeList statusCodeNode = xmlDoc.GetElementsByTagName("entityStatusCode");
                XmlNodeList entityTypeNode = xmlDoc.GetElementsByTagName("entityDescription");
                XmlNodeList descriptionNode = xmlDoc.GetElementsByTagName("organisationName");

                _abnStatus = (statusCodeNode != null && statusCodeNode.Count > 0) ? statusCodeNode[0].InnerText : "";
                _entityType = (entityTypeNode != null && entityTypeNode.Count > 0) ? entityTypeNode[0].InnerText : "";
                _entityName = (descriptionNode != null && descriptionNode.Count > 0) ? descriptionNode[0].InnerText : "";

            }
            catch (Exception ex)
            {
                _error = true;
                _exception = ex.Message;
            }
        }
    }
}
