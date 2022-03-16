<!-- This stylesheet converts the BAI2 xml file to the schema of BankStmtISOService.
	-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:msxsl="urn:schemas-microsoft-com:xslt" exclude-result-prefixes="msxsl"
                xmlns:bai2="http://schemas.microsoft.com/dynamics/2008/01/services/BankStmtService/"
                xmlns="http://schemas.microsoft.com/dynamics/2008/01/documents/BankStmt">
  <xsl:output method="xml" omit-xml-declaration="no" version="1.0" encoding="utf-16"/>

  <xsl:template match ="/" >
    <Batch xmlns="http://schemas.microsoft.com/dynamics/2009/06/documents/Batch" xmlns:msxsl="urn:schemas-microsoft-com:xslt">
      <Envelope xmlns="http://schemas.microsoft.com/dynamics/2011/01/documents/Message">
        <Header>
          <Action>http://tempuri.org/BankStmtService/create</Action>
        </Header>
        <Body>
          <MessageParts>
            <xsl:apply-templates/>
          </MessageParts>
        </Body>
      </Envelope>
    </Batch>
  </xsl:template>

  <!-- This template populates the top level table 'Document' (BankStmtISODocument) -->
  <xsl:template match ="BankStmtISO">
    <BankStmt>
      <Document  class="entity">
        <FormatName>BAI</FormatName>
        <FormatVersion>
          <xsl:value-of select="normalize-space(FileHeader/VersionNumber)"/>
        </FormatVersion>
        <xsl:apply-templates select="FileHeader"/>
        <xsl:call-template name="AccountHeader"/>
      </Document>
    </BankStmt>
  </xsl:template>

  <!-- This template populates the 'GroupHeader'table (BankStmtISOGroupHeader) -->
  <xsl:template name="Document" match="FileHeader">
    <Header  class="entity">
      <BlockSize>
        <xsl:choose>
          <xsl:when test ="normalize-space(BlockSize)= ''">0</xsl:when>
          <xsl:otherwise>
            <xsl:value-of select ="normalize-space(BlockSize)"/>
          </xsl:otherwise>
        </xsl:choose>
      </BlockSize>
      <CreationDateTime>
        <xsl:variable name ="creationDate">
          <xsl:value-of  select="normalize-space(FileCreationDate)"></xsl:value-of>
        </xsl:variable>
        <xsl:variable name ="creationTime">
          <xsl:value-of  select="normalize-space(FileCreationTime)"></xsl:value-of>
        </xsl:variable>
        <xsl:value-of select="bai2:convertToDateTime($creationDate, $creationTime)"/>
      </CreationDateTime>
      <MessageIdentification>
        <xsl:value-of select ="normalize-space(FileIdNumber)"/>
      </MessageIdentification> 
      <PhysicalRecordLength>
        <xsl:choose>
          <xsl:when test ="normalize-space(PhysicalRecordLength)= ''">0</xsl:when>
          <xsl:otherwise>
            <xsl:value-of select ="normalize-space(PhysicalRecordLength)"/>
          </xsl:otherwise>
        </xsl:choose>
      </PhysicalRecordLength>
      <Sender class="entity">
        <xsl:call-template name="PartyId">
          <xsl:with-param name ="OrgId">
            <xsl:value-of select="normalize-space(SenderId)"/>
          </xsl:with-param>
        </xsl:call-template>
      </Sender>
      <Recipient class="entity">
        <xsl:call-template name="PartyId">
          <xsl:with-param name ="OrgId">
            <xsl:value-of select="normalize-space(RecieverId)"/>
          </xsl:with-param>
        </xsl:call-template>
      </Recipient>
    </Header>
  </xsl:template>

  <!-- This template populates the 'AccountStatement' table (BankStmtISOAccountStatement) -->
  <xsl:template name="AccountHeader">
    <xsl:for-each select="//GroupHeader">
      <xsl:variable name="actGrp" select ="."></xsl:variable>
      <xsl:variable name="actGrpTrlr" select ="//GroupTrailer[@accountGroup=$actGrp/@accountGroup]"/>
      <xsl:for-each select="//AccountIdentifierAndSummaryStatus[@accountGroup=$actGrp/@accountGroup]">
        <xsl:variable name="act" select ="."></xsl:variable>
        <xsl:variable name="actTrlr" select ="//AccountTrailer[@accountGroup=$actGrp/@accountGroup and @transactionGroup= $act/@transactionGroup] "/>
        <xsl:variable name="transactions" select="//TransactionDetails[@accountGroup=$actGrp/@accountGroup and @transactionGroup= $act/@transactionGroup] "/>
        <AccountStatement  class="entity">
          <AccountCurrency>
            <xsl:variable name ="currencyVal">
              <xsl:value-of select ="normalize-space(CurrencyCode)"/>
            </xsl:variable>
            <xsl:choose>
              <xsl:when test="$currencyVal=''">
                <xsl:value-of select ="normalize-space($actGrp/CurrencyCode)"/>
              </xsl:when>
              <xsl:otherwise>
                <xsl:value-of select ="normalize-space($currencyVal)"/>
              </xsl:otherwise>
            </xsl:choose>
          </AccountCurrency>
          <AccountIdOtherId>
			<xsl:variable name="accountnumber">
				<xsl:value-of select ="normalize-space(CustomerAccountNumber)"/>
			</xsl:variable>
			<xsl:variable name="metLengthOfString" select="string-length($accountnumber)"/>
			<xsl:value-of select ="substring($accountnumber,7,$metLengthOfString)"/>
          </AccountIdOtherId>
          <AsOfDateModifier>
            <xsl:choose>
              <xsl:when test ="normalize-space($actGrp/AsOfDateModifier)= ''">0</xsl:when>
              <xsl:otherwise>
                <xsl:value-of select ="normalize-space($actGrp/AsOfDateModifier)"/>
              </xsl:otherwise>
            </xsl:choose>
          </AsOfDateModifier>
          <BankStatementType>Reconciliation</BankStatementType>
          <xsl:variable name ="StatementDate">
            <xsl:variable name ="fromDate">
              <xsl:value-of select ="normalize-space($actGrp/AsOfDate)"/>
            </xsl:variable>
            <xsl:variable name="fromTime">
              <xsl:value-of select ="normalize-space($actGrp/AsOfTime)"/>
            </xsl:variable>
            <xsl:value-of select="bai2:convertToDateTime($fromDate, $fromTime)"/>
          </xsl:variable>
          <FromDateTime>
            <xsl:value-of select ="$StatementDate"/>
          </FromDateTime>
          <GroupControlTotal>
            <xsl:call-template name ="DivideByHundred">
              <xsl:with-param name ="strToDivide">
                <xsl:value-of select ="normalize-space($actTrlr/AccountControlTotal)"/>
              </xsl:with-param>
            </xsl:call-template>
          </GroupControlTotal>
          <GroupStatus>
            <xsl:value-of select ="normalize-space($actGrp/GroupStatus)"/>
          </GroupStatus>
          <Identification>
            <xsl:value-of select ="normalize-space($StatementDate)"/>
          </Identification>
          <ToDateTime>
            <xsl:value-of select ="$StatementDate"/>
          </ToDateTime>
          <TotalAccountsInGroup>
            <xsl:value-of select ="normalize-space($actGrpTrlr/NumberOfAccounts)"/>
          </TotalAccountsInGroup>
          <TotalRecordsInGroup>
            <xsl:value-of select ="normalize-space($actGrpTrlr/NumberOfRecords)"/>
          </TotalRecordsInGroup>
          <Originator class="entity">
            <xsl:call-template name="PartyId">
              <xsl:with-param name ="OrgId">
                <xsl:value-of select="normalize-space($actGrp/OriginatorId)"/>
              </xsl:with-param>
            </xsl:call-template>
          </Originator>
          <xsl:call-template name ="CashBalance"/>
          <UltimateReceiver  class="entity">
            <xsl:call-template name="PartyId">
              <xsl:with-param name ="OrgId">
                <xsl:value-of select="normalize-space($actGrp/UltimateReceiverId)"/>
              </xsl:with-param>
            </xsl:call-template>
          </UltimateReceiver>
          <xsl:call-template name ="ReportEntry">
            <xsl:with-param name="transactions" select ="$transactions">
            </xsl:with-param>
            <xsl:with-param name="transactionsDate" select ="$StatementDate">
            </xsl:with-param>
          </xsl:call-template>
        </AccountStatement>
      </xsl:for-each>
    </xsl:for-each>
  </xsl:template>

  <!-- This template populates the table 'PartyIdentification_*' (BankStatementISOPartyIdentification) -->
  <xsl:template name="PartyId">
    <xsl:param name ="OrgId" select ="''"/>
    <Name>
      <xsl:value-of select="$OrgId" />
    </Name>
    <PartyIdOrganisationGenericOrgId>
      <xsl:value-of select="$OrgId" />
    </PartyIdOrganisationGenericOrgId>
  </xsl:template>
  
  <!-- This template populates the table 'CashBalance' BankStatementISOCashBalance -->
  <xsl:template name="CashBalance">
    <xsl:for-each select ="SummaryItem">
      <AccountStatementCashBalance class="entity">
        <xsl:variable name ="TypeCode">
          <xsl:value-of select="normalize-space(TypeCode)"/>
        </xsl:variable>
        <xsl:variable name ="FundType">
          <xsl:value-of select="normalize-space(./FundAvailibility/FundType)"/>
        </xsl:variable>
        <xsl:variable name ="OriginAmount">
          <xsl:call-template name ="DivideByHundred">
            <xsl:with-param name ="strToDivide">
              <xsl:choose>
                <xsl:when test ="normalize-space(Amount)= ''">0</xsl:when>
                <xsl:otherwise>
                  <xsl:value-of select ="normalize-space(Amount)"/>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:with-param>
          </xsl:call-template>
        </xsl:variable>
        <AmountCreditDebitIndicator>
          <xsl:call-template name ="GetAmountCreditDebitIndicator">
            <xsl:with-param name ="OriginAmount" select ="normalize-space($OriginAmount)"></xsl:with-param>
          </xsl:call-template>
        </AmountCreditDebitIndicator>
        <BankStatementBalanceType>
          <xsl:choose>
            <xsl:when test ="normalize-space($TypeCode)= '010'">Opening</xsl:when>
            <xsl:when test ="normalize-space($TypeCode)= '015'">Closing</xsl:when>
            <xsl:otherwise>None</xsl:otherwise>
          </xsl:choose>
        </BankStatementBalanceType>
        <CashBalanceAmount>
          <xsl:call-template name ="GetAmountValue">
            <xsl:with-param name ="OriginAmount" select ="normalize-space($OriginAmount)"></xsl:with-param>
          </xsl:call-template>
        </CashBalanceAmount>
        <FundsType>
          <xsl:choose>
            <xsl:when test ="normalize-space($FundType)= ''">Z</xsl:when>
            <xsl:otherwise>
              <xsl:value-of select ="normalize-space($FundType)"/>
            </xsl:otherwise>
          </xsl:choose>
        </FundsType>
        <ItemCount>
          <xsl:choose>
            <xsl:when test ="normalize-space(ItemCount)= ''">0</xsl:when>
            <xsl:otherwise>
              <xsl:value-of select ="normalize-space(ItemCount)"/>
            </xsl:otherwise>
          </xsl:choose>
        </ItemCount>
        <TypeCode>
          <xsl:value-of select ="normalize-space($TypeCode)"/>
        </TypeCode>
        <xsl:call-template   name="FundAvailibility" >
          <xsl:with-param name ="FundType" select ="normalize-space($FundType)"></xsl:with-param>
          <xsl:with-param name ="NodeName" select="'CashBalanceCashBalAvl'"></xsl:with-param>
        </xsl:call-template>
      </AccountStatementCashBalance>
    </xsl:for-each>
  </xsl:template>

  <!-- This template populates the table 'CashBalanceAvailibility_*' (BankStatementISOCashBalanceAvailibility) -->
  <xsl:template name="FundAvailibility">
    <xsl:param name="FundType" ></xsl:param>
    <xsl:param name="NodeName"></xsl:param>
    <xsl:choose>
      <xsl:when test ="$FundType='D'">
        <xsl:for-each select="FundAvailibility/VariableDistributedAvailibility/Distribution">
          <xsl:element name="{$NodeName}">
            <xsl:attribute name="class">
              <xsl:value-of select="'entity'"/>
            </xsl:attribute>
            <ActualDate>
              <xsl:value-of select="bai2:convertToDateTime('', '')"/>
            </ActualDate>
            <Amount>
              <xsl:call-template name ="DivideByHundred">
                <xsl:with-param name ="strToDivide">
                  <xsl:choose>
                    <xsl:when test ="normalize-space(Amount)= ''">0</xsl:when>
                    <xsl:otherwise>
                      <xsl:value-of select ="normalize-space(Amount)"/>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:with-param>
              </xsl:call-template>
            </Amount>
            <NumberOfDays>
              <xsl:choose>
                <xsl:when test ="normalize-space(NumberOfDays)= ''">0</xsl:when>
                <xsl:otherwise>
                  <xsl:value-of select ="normalize-space(NumberOfDays)"/>
                </xsl:otherwise>
              </xsl:choose>
            </NumberOfDays>
          </xsl:element>
        </xsl:for-each>
      </xsl:when>

      <xsl:when test="$FundType='V'">
        <xsl:for-each select ="FundAvailibility/ValueDatedAvailibility">
          <xsl:element name="{$NodeName}">
            <xsl:attribute name="class">
              <xsl:value-of select="'entity'"/>
            </xsl:attribute>
            <ActualDate>
              <xsl:variable name="actualDate">
                <xsl:value-of select ="normalize-space(ValueDate)"/>
              </xsl:variable>
              <xsl:variable name ="actualTime">
                <xsl:value-of select ="normalize-space(ValueTime)"/>
              </xsl:variable>
              <xsl:value-of select="bai2:convertToDateTime($actualDate, $actualTime)"/>
            </ActualDate>
            <Amount>0.00</Amount>
            <NumberOfDays>0</NumberOfDays>
          </xsl:element>
        </xsl:for-each>
      </xsl:when>

      <xsl:when test="$FundType='S'">
        <xsl:for-each select ="FundAvailibility/DistributedAvailibility">
          <xsl:element name="{$NodeName}">
            <xsl:attribute name="class">
              <xsl:value-of select="'entity'"/>
            </xsl:attribute>
            <ActualDate>
              <xsl:value-of select="bai2:convertToDateTime('', '')"/>
            </ActualDate>
            <Amount>
              <xsl:call-template name ="DivideByHundred">
                <xsl:with-param name ="strToDivide">
                  <xsl:choose>
                    <xsl:when test ="normalize-space(Immediate)= ''">0</xsl:when>
                    <xsl:otherwise>
                      <xsl:value-of select ="normalize-space(Immediate)"/>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:with-param>
              </xsl:call-template>
            </Amount>
            <NumberOfDays>0</NumberOfDays>
          </xsl:element>
          <xsl:element name="{$NodeName}">
            <xsl:attribute name="class">
              <xsl:value-of select="'entity'"/>
            </xsl:attribute>
            <ActualDate>
              <xsl:value-of select="bai2:convertToDateTime('', '')"/>
            </ActualDate>
            <Amount>
              <xsl:call-template name ="DivideByHundred">
                <xsl:with-param name ="strToDivide">
                  <xsl:choose>
                    <xsl:when test ="normalize-space(OneDay)= ''">0</xsl:when>
                    <xsl:otherwise>
                      <xsl:value-of select ="normalize-space(OneDay)"/>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:with-param>
              </xsl:call-template>
            </Amount>
            <NumberOfDays>1</NumberOfDays>
          </xsl:element>
          <xsl:element name="{$NodeName}">
            <xsl:attribute name="class">
              <xsl:value-of select="'entity'"/>
            </xsl:attribute>
            <ActualDate>
              <xsl:value-of select="bai2:convertToDateTime('', '')"/>
            </ActualDate>
            <Amount>
              <xsl:call-template name ="DivideByHundred">
                <xsl:with-param name ="strToDivide">
                  <xsl:choose>
                    <xsl:when test ="normalize-space(MoreThanOneDay)= ''">0</xsl:when>
                    <xsl:otherwise>
                      <xsl:value-of select ="normalize-space(MoreThanOneDay)"/>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:with-param>
              </xsl:call-template>
            </Amount>
            <NumberOfDays>2</NumberOfDays>
          </xsl:element>
        </xsl:for-each>
      </xsl:when>
    </xsl:choose>
  </xsl:template>

  <!-- This template populates the table 'ReportEntry' (BankStatementISOReportEntry) -->
  <xsl:template name ="ReportEntry">
    <xsl:param name="transactions">
    </xsl:param>
    <xsl:param name="transactionsDate">
    </xsl:param>
    <xsl:for-each select ="$transactions">
      <AccountStatementReportEntry class="entity">
        <AccountServicerReference>
          <xsl:value-of select ="normalize-space(CustomerReferenceNumber)"/>
        </AccountServicerReference>
        <AdditionalEntryInformation>
          <xsl:value-of select ="Text"/>
        </AdditionalEntryInformation>
        <xsl:variable name ="OriginAmount">
          <xsl:call-template name ="DivideByHundred">
            <xsl:with-param name ="strToDivide">
              <xsl:choose>
                <xsl:when test ="normalize-space(Amount)= ''">0</xsl:when>
                <xsl:otherwise>
                  <xsl:value-of select ="normalize-space(Amount)"/>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:with-param>
          </xsl:call-template>
        </xsl:variable>
        <Amount>
          <xsl:value-of select ="$OriginAmount"/>
        </Amount>
        <AmountCreditDebitIndicator>
          <xsl:choose>
            <xsl:when test ="(normalize-space(TypeCode) &gt;= 400) and (normalize-space(TypeCode) &lt;= 699)">Credit</xsl:when>
            <xsl:when test ="(normalize-space(TypeCode) &gt;= 100) and (normalize-space(TypeCode) &lt;= 399)">Debit</xsl:when>
	    <xsl:when test ="(normalize-space(TypeCode) &gt;= 950) and (normalize-space(TypeCode) &lt;= 988)">Credit</xsl:when>
	    <xsl:when test ="(normalize-space(TypeCode) &gt;= 905) and (normalize-space(TypeCode) &lt;= 938)">Debit</xsl:when>
            <xsl:otherwise>Debit</xsl:otherwise>
          </xsl:choose>
        </AmountCreditDebitIndicator>
        <BookingDateTime>
          <xsl:value-of select ="$transactionsDate"/>
        </BookingDateTime>
        <EntryReference>
          <xsl:value-of select="normalize-space(BankReferenceNumber)"/>
        </EntryReference>
        <ProprietaryBankTransactionCode>
          <xsl:value-of select ="normalize-space(TypeCode)"/>
        </ProprietaryBankTransactionCode>
        <ReferenceNumber>
          <xsl:value-of select ="normalize-space(CustomerReferenceNumber)"/>
        </ReferenceNumber>
        <ReversalIndicator>
          <xsl:call-template name ="GetAmountReversal">
            <xsl:with-param name ="OriginAmount" select ="normalize-space($OriginAmount)"></xsl:with-param>
          </xsl:call-template>
        </ReversalIndicator>
        <xsl:variable name ="FundType">
          <xsl:value-of select="normalize-space(./FundAvailibility/FundType)"/>
        </xsl:variable>
        <xsl:call-template   name="FundAvailibility" >
          <xsl:with-param name ="FundType" select ="normalize-space($FundType)"></xsl:with-param>
          <xsl:with-param name ="NodeName" select="'ReportEntryCashBalAvl'"></xsl:with-param>
        </xsl:call-template>
      </AccountStatementReportEntry>
    </xsl:for-each>
  </xsl:template>

  <!-- This is a simple string replacement helper template. It had to be written since AIF does not
	support XSLT 2.0 and XSLT 1.0 does not have this function built in.
	Parameters:
	txt				= The text on which replacement is to be performed
	strToBeReplaced = The string in 'txt' that needs replacement
	strToReplace	= The string that replaces 'strToBeReplaced' in 'txt'-->
  <xsl:template name="strReplace">
    <xsl:param name="txt" />
    <xsl:param name="strToBeReplaced" />
    <xsl:param name="strToReplace" />
    <xsl:choose>
      <xsl:when test="contains($txt, $strToBeReplaced)">
        <xsl:value-of select="substring-before($txt,$strToBeReplaced)" />
        <xsl:value-of select="$strToReplace" />
        <xsl:call-template name="strReplace">
          <xsl:with-param name="txt" select="substring-after($txt,$strToBeReplaced)" />
          <xsl:with-param name="strToBeReplaced" select="$strToBeReplaced" />
          <xsl:with-param name="strToReplace" select="$strToReplace" />
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$txt" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <!-- This is a simple template to convert the amount representation in the BAI format to the
    amount representation as understood by AX (via AIF). Since both US an CA have 2 implied decimals
    we just divide the number by hundred-->
  <xsl:template name ="DivideByHundred">
    <xsl:param name ="strToDivide"/>
    <xsl:value-of select="bai2:divideByHundred($strToDivide)"/>
  </xsl:template>

  <xsl:template name ="GetAmountValue">
    <xsl:param name ="OriginAmount" select="''"/>
    <xsl:choose>
      <xsl:when test ="$OriginAmount=''">
        <xsl:value-of select="0"/>
      </xsl:when>
      <xsl:when test ="$OriginAmount &gt; 0">
        <xsl:value-of select ="$OriginAmount" />
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select ="-$OriginAmount" />
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template name ="GetAmountReversal">
    <xsl:param name ="OriginAmount"/>
    <xsl:choose>
      <xsl:when test ="$OriginAmount &lt; 0">Yes</xsl:when>
      <xsl:otherwise>No</xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template name ="GetAmountCreditDebitIndicator">
    <xsl:param name ="OriginAmount"/>
    <xsl:choose>
      <xsl:when test ="$OriginAmount &lt; 0">Credit</xsl:when>
      <xsl:otherwise>Debit</xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <msxsl:script language="C#" implements-prefix="bai2">
    <![CDATA[
     public string divideByHundred(string strToDivide)
     {
        return ((Double.Parse(strToDivide))/100.00).ToString("0.00");
     }
      
	   public string convertToDateTime(string strDate, string strTime)
     {
        DateTime dateTime;
        string stringToConvert;
        
        if (strDate == "") return "1900-01-01T00:00:00Z";
        // 2400 is end of day according to BAI2 standard. 
        if (strTime == "2400")
        {
            dateTime = DateTime.ParseExact(strDate, "yyMMdd", System.Globalization.DateTimeFormatInfo.InvariantInfo);
            dateTime = dateTime.AddDays(1).AddSeconds(-1);
        }
        else
        {
            if (strTime == "")
            {
                strTime = "0000";
            }
        
            stringToConvert = strDate + strTime;
            dateTime = DateTime.ParseExact(stringToConvert, "yyMMddHHmm", System.Globalization.DateTimeFormatInfo.InvariantInfo);
        }
        
        return dateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ");
     }
     ]]>
  </msxsl:script>
</xsl:stylesheet>
