CREATE PROCEDURE [dbo].[CW_selectAccountTransactions_AI_csv]  
	@AccountListCsv					Varchar(max),    
	@SinceInception					BIT = 0,
	@StartDate						DATETIME = NULL,
	@EndDate						DATETIME = NULL	 
AS    
/********************************************************************************************
Stored Procedure: $HeaderUTC$
---------------------------------------------------------------------------------------------
Version :   $Revision$
---------------------------------------------------------------------------------------------
Purpose :	Return AI account transaction data for a single account or an account group.
---------------------------------------------------------------------------------------------
Revions	:	1.0		08/02/2016	Steve Humpal	Updated from RE_getAccountTransactions_AI_csv 
			2.0		01/20/2021	Ayelet Soffer	Do not d_rop temp tables, truncate them instead
			2.1		01/04/2022	Steve Humpal	Updated to include PSTransferFlag
			2.2		04/19/2022	Steve Humpal	Updated to include ExcludeFromClassification
			2.3		08/13/2022	Steve Humpal	Updated to include SecurityNo
			2.4     05/22/2023 Ratul Pramanick	Implemented InterestReinvest Flag
---------------------------------------------------------------------------------------------
Unit Tests:
		exec  Reporting.dbo.CW_selectAccountTransactions_AI_csv
			@AccountListCsv = '123123,4422244' ,   
			@SinceInception = 0,
			@StartDate = '1/1/2011',
			@EndDate = '12/31/2012'
---------------------------------------------------------------------------------------------
********************************************************************************************/


SET NOCOUNT ON   
SET Transaction Isolation Level Read Uncommitted

DECLARE @COB_StartDate	DATETIME

IF @SinceInception = 1
BEGIN
	SELECT @COB_StartDate = '07/01/2005'
END
ELSE
BEGIN
	SELECT @COB_StartDate = PortfolioManager.dbo.fn_GetPriceDate(@StartDate)   	
END

IF OBJECT_ID('tempdb..#AccountsAI') IS NULL       
BEGIN
		CREATE TABLE #AccountsAI (AccountID		INT, 
					AccountLocationCode	INT,
					LPLAccountNo			VARCHAR(8),
					RepId					CHAR(4) NULL,
					SponsorCode			VARCHAR(4), 
					SponsorAccountNo		VARCHAR(20), 
					SponsorType			VARCHAR(1),
					SSN					VARCHAR(9),
					AsOfDate				DateTime
		,INDEX [idx_Accounts_tmp] CLUSTERED (AccountID))
		
END
ELSE
BEGIN
	TRUNCATE TABLE #AccountsAI
END

IF OBJECT_ID('tempdb..#csvAccountsAI') IS NULL       
BEGIN
CREATE TABLE #csvAccountsAI 
		(	
		accountId int
		)
END
ELSE
BEGIN
	TRUNCATE TABLE #csvAccountsAI
END

/*******************************************************************
PARSE CSV ACCOUNT IDS INTO A TABLE
*******************************************************************/

INSERT INTO #csvAccountsAI(accountId)
SELECT Value from Reporting.dbo.udfParseCsv (@AccountListCSV) option(maxrecursion 0)

	insert into #AccountsAI
	(
		AccountId,
		AccountLocationCode,
		LPLAccountNo,
		RepId,
		SponsorCode,
		SponsorAccountNo,
		SponsorType,
		SSN,
		AsOfDate
	)
	select
		[AccountId] = Acct.AccountId,
		[AccountLocationCode] = A.AccountLocationCode,
		[LPLAccountNo] = A.LPLAccountNo, 
		[RepId] = A.RepID, 		 
		[SponsorCode] = A.SponsorCode,
		[SponsorAccountNo] = A.SponsorAccountNo,
		[SponsorType] = A.SponsorType,
		[SSN] = A.SSNTaxID,
		[AsOfDate] = isnull(Aod.AsOfDate, A.AsOfDate)
		
	from #csvAccountsAI as [Acct]
		inner join lplcustomer.dbo.account as [A]
			on [Acct].AccountId = [A].AccountId
		left outer join LPLCustomer.dbo.AsOfDates AS [Aod]
			on [A].SponsorCode = [Aod].SponsorCode 
			and [A].SponsorType = [Aod].SponsorType
			


/*******************************************************************************
  Fetch AI Flow Fixed Transactions
********************************************************************************/
SELECT 
	'AIFF'												AS TransSource, 
	l.AccountID											AS AccountID,			
	l.AccountLocationCode								AS AccountLocationCode,
	ISNULL(a.LPLAccountNo,'')							AS LPLAccountNo,
	l.SponsorAccountNo									AS Accountno,			
	ISNULL(s.SecurityID,-1)								AS SecurityID,			
	T.Quantity,																	--PE: ISNULL(T.Quantity,0)
	ISNULL(T.AMOUNT,0)									AS Amount,
	ISNULL(S.SecuritySourceCode, 0)						AS SecuritySourceCode,
	l.SponsorAccountNo									AS SponsorAccountNo,
	CAST(ISNULL(tcfm.FeeFlag,0) AS INT)                 AS FEEFLAG,
	CAST(ISNULL(tcfm.DividendFlag,0) AS INT)            AS DIVIDENDFLAG,
	CAST(ISNULL(tcfm.CAPGAINFLAG,0) AS INT)             AS CAPGAINFLAG,
	CAST(ISNULL(tcfm.DividendReinvestFlag,0) AS INT)    AS DIVIDENDREINVESTFLAG,  
    CAST(ISNULL(tcfm.CapGainReinvestFlag,0) AS INT)     AS CAPGAINREINVESTFLAG, 
	CAST(ISNULL(tcfm.InterestFlag,0) AS INT)            AS INTERESTFLAG,
	CAST(ISNULL(tcfm.PrincipalPaymentFlag,0)AS INT)     AS PRINCIPALPAYMENTFLAG,
	CAST(ISNULL(tcfm.ACCOUNTFLOWFLAG, 0) AS INT)        AS FLOWFLAG,
	CAST(ISNULL(tcfm.SECURITYFLOWFLAG, 0) AS INT)       AS SECURITYFLOWFLAG,
	CAST(ISNULL(tcfm.CheckForInternalExchangeFlag,0) AS INT)	AS CheckForInternalExchangeFlag,
	CAST(ISNULL(tcfm.ApplyOffSettingFlowFlag,0) AS INT)			AS ApplyOffSettingFlowFlag,
	0						AS InterestReinvestFlag,
	T.ExtFlowAmt * -1		AS ExtFlowAmt,	--PE: T.ExtFlowAmt (does not negate)
	T.IntFlowAmt * -1		AS IntFlowAmt,	--PE: T.IntFlowAmt (does not negate)
	ISNULL(tcfm.REVERSALCODE,'0')						AS REVERSALCODE,
	'D'                                                 AS RECORDTYPE,
	ISNULL(tcfm.Code, 'N/A')							AS SOURCECODE,	--PE: PE also returns ISNULL(tcfm.Code, 'missing') AS TRANSACTIONFLOWCODE (see PE Fields added below)
	0													AS SyntheticOpenCloseFlag,
	A.SponsorCode,
	ISNULL((SELECT 1 FROM BETA.DBO.BETA_SECURITY_MSTR SM 
	WHERE SM.SECURITYNO = S.SECURITYNO AND MLPCODE IN ('I','B')), 0) AS REITFlag,
	1								AS UnitQuantity,	--PE: CAST(0 AS DECIMAL) AS UNITQUANTITY
	CAST(1 AS DECIMAL)				AS FACTOR,			
	0								AS DIRECTFEE,
	20								AS TRANSACTIONSOURCE,
	ISNULL(S.PMSecurityTypeID, 0)	AS SecurityTypeID,	
	''								AS BuySellInd,				
	NULL							AS Price,					
	0								AS WholeConversionFactor,	
	ISNULL(S.SecurityIdentifier,'')	AS SecurityIdentifier,		
	''								AS PMSecTypeDescription,
	''								AS AssetClassCode,
	T.ActivityDate					AS ActivityAsOfDate,
	NULL							AS Cusip_Isin,	
	COALESCE(so.SecurityDescription,S.[Description],tdbo.TransactionDescription,tcfm.Description,'') AS TransactionDescription, 
	''				AS SubsidiaryNo,
	''				AS AccountType,
	''				AS RanDAccountHld,
	''				AS Desc1,
	''				AS Desc2,
	Classification = 
		CASE 			
			WHEN atm1.SrcTransPK IS NOT NULL THEN 2
			WHEN atm2.DestTransPK IS NOT NULL THEN 1
			WHEN ate.TransPK IS NOT NULL THEN 6			
			ELSE 0 
		END,
	ISNULL(L.SSN,'') AS SSNTaxID,
	0				AS TransferFlag,
	0				AS JournalFlag,
	ISNULL(S.CUSIP,'') AS CUSIP,
	ISNULL(S.Symbol,'') AS Symbol,
	ISNULL(tcfm.Description, 'N/A') AS SourceCodeDescription,
	T.TransactionPrimaryKey  AS TransactionPrimaryKey,
	T.DataSource,
	COALESCE(atm1.SrcTransPK, atm2.SrcTransPK) AS SrcTransPK,
	COALESCE(atm1.DestTransPK, atm2.DestTransPK) AS DestTransPK,
	COALESCE(atm1.SrcActLocCode, atm2.SrcActLocCode) AS SrcActLocCode,
	COALESCE(atm1.DestActLocCode, atm2.DestActLocCode) AS DestActLocCode,
	CAST(ISNULL(tcfm.InvestmentRedemptionFlag, 0) AS INT) AS InvestmentRedemptionFlag,
	0 AS ChangeSign,
	1 AS AccountTypeCode,
	CAST(ISNULL(tcfm.TradeFlag, 0) AS INT) AS TradeFlag,
	tcfm.PSTransferFlag AS PSTransferFlag,
	tcfm.ExcludeFromClassification,
	ISNULL(S.SecurityNo, 0) as SecurityNo
From #AccountsAI L 
	JOIN (select 
					AccountId	,
					LPLAccountNo	,
					SponsorAccountNo	,
					SponsorCode

				from LPLCUSTOMER.DBO.ACCOUNTAIN  
				
				union all 
				
				select 
				AccountId	,
				LPLAccountNo	,
				SponsorAccountNo	,
				SponsorCode	

				from LPLCUSTOMER.DBO.ACCOUNTAI ) A ON L.ACCOUNTID = A.ACCOUNTID
	JOIN PortfolioManager.DBO.FfDirectBusiness T  ON A.SPONSORACCOUNTNO = T.AccountNumber AND A.SPONSORCODE = T.SponsorCode
	LEFT JOIN PortfolioManager.dbo.TransactionDirectBusinessOverride AS tdbo  ON tdbo.TransactionPrimaryKey = T.TransactionPrimaryKey AND tdbo.DataSource = T.DataSource
	LEFT JOIN LPLCUSTOMER.DBO.SecurityAI S  ON T.SecurityID = S.SecurityID
	LEFT JOIN LPLCustomer.dbo.SecurityOverride so  ON S.SecurityId = so.SecurityId  
	LEFT JOIN PortfolioManager.dbo.TransactionCodeFlowMapping tcfm  ON t.TransactionCode = tcfm.code AND tcfm.Source = t.TransactionSource AND tcfm.Source = 'FanMail'
	LEFT JOIN (SELECT atm.SrcTransPK, atm.SrcActLocCode, min(atm.DestTransPK) as DestTransPK, min(atm.DestActLocCode) as DestActLocCode
		FROM #AccountsAI acct join PortfolioManager.dbo.ActivityTransferMapping atm  
		ON acct.SponsorAccountNo = atm.SrcAccountNumber
		GROUP BY atm.SrcTransPK, atm.SrcActLocCode) atm1 
		 ON atm1.SrcTransPK = T.TransactionPrimaryKey and atm1.SrcActLocCode = l.AccountLocationCode
	LEFT JOIN (SELECT min(atm.SrcTransPK) AS SrcTransPK, min(atm.SrcActLocCode) AS SrcActLocCode, atm.DestTransPK, atm.DestActLocCode
		FROM #AccountsAI acct join PortfolioManager.dbo.ActivityTransferMapping atm  
		ON acct.SponsorAccountNo = atm.DestAccountNumber
		GROUP BY atm.DestTransPK, atm.DestActLocCode) atm2  
		 ON atm2.DestTransPK = T.TransactionPrimaryKey and atm2.DestActLocCode = l.AccountLocationCode
	LEFT JOIN PortfolioManager.dbo.ActivityTransferExclusions ate  ON ate.TransPK = t.TransactionPrimaryKey and ate.AccountLocationCode = l.AccountLocationCode
WHERE t.ActivityDate >= @COB_StartDate 
	AND t.ActivityDate <= L.AsOfDate
	and t.DataSource in ('AI', 'AI Synthetic', 'AI FlowFixed')

UNION ALL

/*******************************************************************************
  Fetch AI Natural Transactions
********************************************************************************/
SELECT  
	'AI'												AS TransSource, 
	l.AccountID											AS AccountID,				
	l.AccountLocationCode								AS AccountLocationCode,
	ISNULL(a.LPLAccountNo,'')							AS LPLAccountNo,
	l.SponsorAccountNo									AS Accountno,
	ISNULL(s.SecurityID,-1)								AS SecurityID,				
	T.Quantity,																		--PE: ISNULL(T.Quantity,0)
	ISNULL(T.AMOUNT,0)									AS Amount,
	ISNULL(S.SecuritySourceCode, 0)						AS SecuritySourceCode,
	l.SponsorAccountNo									AS SponsorAccountNo,
	CAST(ISNULL(tcfm.FeeFlag,0) AS INT)                 AS FEEFLAG,
	CAST(ISNULL(tcfm.DividendFlag,0) AS INT)            AS DIVIDENDFLAG,
	CAST(ISNULL(tcfm.CAPGAINFLAG,0) AS INT)             AS CAPGAINFLAG,
	CAST(ISNULL(tcfm.DividendReinvestFlag,0) AS INT)    AS DIVIDENDREINVESTFLAG,  
    CAST(ISNULL(tcfm.CapGainReinvestFlag,0) AS INT)     AS CAPGAINREINVESTFLAG, 
	CAST(ISNULL(tcfm.InterestFlag,0) AS INT)            AS INTERESTFLAG,
	CAST(ISNULL(tcfm.PrincipalPaymentFlag,0)AS INT)     AS PRINCIPALPAYMENTFLAG,
	CAST(ISNULL(tcfm.ACCOUNTFLOWFLAG, 0) AS INT)        AS FLOWFLAG,
	CAST(ISNULL(tcfm.SECURITYFLOWFLAG, 0) AS INT)       AS SECURITYFLOWFLAG,
	CAST(ISNULL(tcfm.CheckForInternalExchangeFlag,0) AS INT)  AS CheckForInternalExchangeFlag,
	CAST(ISNULL(tcfm.ApplyOffSettingFlowFlag,0) AS INT)	AS ApplyOffSettingFlowFlag,
	0													AS InterestReinvestFlag,
	NULL												AS ExtFlowAmt,						
	NULL												AS IntFlowAmt,
	ISNULL(tcfm.REVERSALCODE,'0')						AS REVERSALCODE,
	'D'                                                 AS RECORDTYPE,
	ISNULL(tcfm.Code, 'N/A')							AS SOURCECODE,	--PE: PE also returns ISNULL(tcfm.Code, 'missing') AS TRANSACTIONFLOWCODE (see PE Fields added below)
	0 SyntheticOpenCloseFlag,
	A.SponsorCode,
	ISNULL((SELECT 1 FROM BETA.DBO.BETA_SECURITY_MSTR SM 
	WHERE SM.SECURITYNO = S.SECURITYNO AND MLPCODE IN ('I','B')), 0) AS REITFlag,
	1									AS UnitQuantity,		--PE: CAST(0 AS DECIMAL) AS UNITQUANTITY
	CAST(1 AS DECIMAL)					AS FACTOR,				
	0									AS DIRECTFEE,
	18									AS TRANSACTIONSOURCE,
	ISNULL(S.PMSecurityTypeID, 0)		AS SecurityTypeID,		
	''									AS BuySellInd,				
	NULL								AS Price,					
	0									AS WholeConversionFactor,	
	ISNULL(S.SecurityIdentifier,'')		AS SecurityIdentifier,		
	''									AS PMSecTypeDescription,
	''									AS AssetClassCode,
	ISNULL(T.TradeDate, T.AsOfDate)		AS ActivityAsOfDate,
	NULL								AS Cusip_Isin,			
	COALESCE(so.SecurityDescription,S.[Description],tdbo.TransactionDescription,tc.TransactionDesc,'') AS TransactionDescription, 
	''				AS SubsidiaryNo,
	''				AS AccountType,
	''				AS RanDAccountHld,
	''				AS Desc1,
	''				AS Desc2,
	Classification = 
		CASE 
			WHEN atm1.SrcTransPK IS NOT NULL THEN 2
			WHEN atm2.DestTransPK IS NOT NULL THEN 1
			WHEN ate.TransPK IS NOT NULL THEN 6			
			ELSE 0 
		END,
	ISNULL(L.SSN,'') AS SSNTaxID,
	0				AS TransferFlag,
	0				AS JournalFlag,
	ISNULL(S.CUSIP,'') AS CUSIP,
	ISNULL(S.Symbol,'') AS Symbol,
	ISNULL(tcfm.Description, 'N/A') AS SourceCodeDescription,
	cast(t.TransactionID AS varchar(50)) AS TransactionPrimaryKey,
	'AI'		AS DataSource,
	COALESCE(atm1.SrcTransPK, atm2.SrcTransPK) AS SrcTransPK,
	COALESCE(atm1.DestTransPK, atm2.DestTransPK) AS DestTransPK,
	COALESCE(atm1.SrcActLocCode, atm2.SrcActLocCode) AS SrcActLocCode,
	COALESCE(atm1.DestActLocCode, atm2.DestActLocCode) AS DestActLocCode,
	CAST(ISNULL(tcfm.InvestmentRedemptionFlag,0) AS INT) AS InvestmentRedemptionFlag,
	0 AS ChangeSign,
	1 AS AccountTypeCode,
	CAST(ISNULL(tcfm.TradeFlag, 0) AS INT) AS TradeFlag,
	tcfm.PSTransferFlag AS PSTransferFlag,
	tcfm.ExcludeFromClassification,
	ISNULL(S.SecurityNo, 0) as SecurityNo
FROM #AccountsAI L 
	JOIN (select 
					AccountId	,
					LPLAccountNo	,
					SponsorAccountNo	,
					SponsorCode

				from LPLCUSTOMER.DBO.ACCOUNTAIN  
				
				union all 
				
				select 
				AccountId	,
					LPLAccountNo	,
					SponsorAccountNo	,
					SponsorCode

				from LPLCUSTOMER.DBO.ACCOUNTAI) A ON L.ACCOUNTID = A.ACCOUNTID
	JOIN ALTERNATIVEINVESTMENTS.DBO.ACCOUNTTRANSACTION T  ON A.SPONSORACCOUNTNO = T.COMPANYACCOUNTNO AND A.SPONSORCODE = T.COMPANYCD
	LEFT JOIN PortfolioManager.dbo.TransactionDirectBusinessOverride AS tdbo  
		ON tdbo.DataSource = 'AI' AND tdbo.TransactionPrimaryKey = cast(t.TransactionID AS varchar(50))
	JOIN AlternativeInvestments.dbo.TransactionCode tc ON T.TransactionCd = tc.TransactionCd --Added to fetch description
	LEFT JOIN LPLCUSTOMER.DBO.SecurityAI S  ON T.Cusip = S.Cusip
	LEFT JOIN LPLCustomer.dbo.SecurityOverride so  ON S.SecurityId = so.SecurityId
	LEFT JOIN PortfolioManager.dbo.TransactionCodeFlowMapping tcfm  ON ISNULL(NullIf(left(t.TranDetailCd, 6), ''), left(t.TransactionCd,4)) = tcfm.code AND tcfm.Source = 'FanMail'
	LEFT JOIN (SELECT atm.SrcTransPK, atm.SrcActLocCode, min(atm.DestTransPK) as DestTransPK, min(atm.DestActLocCode) as DestActLocCode
		FROM #AccountsAI acct join PortfolioManager.dbo.ActivityTransferMapping atm  
		ON acct.SponsorAccountNo = atm.SrcAccountNumber
		GROUP BY atm.SrcTransPK, atm.SrcActLocCode) atm1 
		 ON atm1.SrcTransPK = cast(t.TransactionID AS varchar(50)) and atm1.SrcActLocCode = l.AccountLocationCode
	LEFT JOIN (SELECT min(atm.SrcTransPK) AS SrcTransPK, min(atm.SrcActLocCode) AS SrcActLocCode, atm.DestTransPK, atm.DestActLocCode
		FROM #AccountsAI acct join PortfolioManager.dbo.ActivityTransferMapping atm  
		ON acct.SponsorAccountNo = atm.DestAccountNumber
		GROUP BY atm.DestTransPK, atm.DestActLocCode) atm2  
		 ON atm2.DestTransPK = cast(t.TransactionID AS varchar(50)) and atm2.DestActLocCode = l.AccountLocationCode
	LEFT JOIN PortfolioManager.dbo.ActivityTransferExclusions ate  ON ate.TransPK = cast(t.TransactionID AS varchar(50)) and ate.AccountLocationCode = l.AccountLocationCode
	WHERE 
	ISNULL(T.TradeDate, T.AsOfDate) >= @COB_StartDate 
	AND ISNULL(T.TradeDate, T.AsOfDate) <= L.AsOfDate
	AND NOT EXISTS ( 
		SELECT 1 from PORTFOLIOMANAGER.dbo.FfDirectBusiness W  
		where 
			 w.DataSource='AI' 
			 AND W.TransactionPrimaryKey=cast(t.TransactionID AS varchar(50)) AND W.Synthetic ='N'			 
			 and W.Synthetic ='N'
		 )

UNION ALL

/*******************************************************************************
  Fetch AI Synthetic Transactions
********************************************************************************/
SELECT 
	'AIS'												AS TransSource, 
	l.AccountID											AS AccountID,		
	l.AccountLocationCode								AS AccountLocationCode,
	ISNULL(a.LPLAccountNo,'')							AS LPLAccountNo,
	l.SponsorAccountNo									AS Accountno,
	ISNULL(s.SecurityID,-1)								AS SecurityID,		
	T.Quantity,																--PE: ISNULL(T.Quantity,0)
	COALESCE(NULLIF(t.Amount,0),t.Quantity*hp.Price,0)	AS AMOUNT,
	ISNULL(S.SecuritySourceCode, 0)						AS SecuritySourceCode,
	l.SponsorAccountNo									AS SponsorAccountNo,
	CAST(ISNULL(tcfm.FeeFlag,0) AS INT)                 AS FEEFLAG,
	CAST(ISNULL(tcfm.DividendFlag,0) AS INT)            AS DIVIDENDFLAG,
	CAST(ISNULL(tcfm.CAPGAINFLAG,0) AS INT)             AS CAPGAINFLAG,
	CAST(ISNULL(tcfm.DividendReinvestFlag,0) AS INT)    AS DIVIDENDREINVESTFLAG,  
    CAST(ISNULL(tcfm.CapGainReinvestFlag,0) AS INT)     AS CAPGAINREINVESTFLAG, 
	CAST(ISNULL(tcfm.InterestFlag,0) AS INT)            AS INTERESTFLAG,
	CAST(ISNULL(tcfm.PrincipalPaymentFlag,0)AS INT)     AS PRINCIPALPAYMENTFLAG,
	CAST(ISNULL(tcfm.ACCOUNTFLOWFLAG, 0) AS INT)        AS FLOWFLAG,
	CAST(ISNULL(tcfm.SECURITYFLOWFLAG, 0) AS INT)       AS SECURITYFLOWFLAG,
	CAST(ISNULL(tcfm.CheckForInternalExchangeFlag,0) AS INT)	AS CheckForInternalExchangeFlag,
	CAST(ISNULL(tcfm.ApplyOffSettingFlowFlag,0) AS INT)			AS ApplyOffSettingFlowFlag,
	0													AS InterestReinvestFlag,		
	NULL												AS ExtFlowAmt,						
	NULL												AS IntFlowAmt,
	ISNULL(tcfm.REVERSALCODE,'0')						AS REVERSALCODE,
	'D'													AS RECORDTYPE,
	ISNULL(tcfm.Code, 'N/A')							AS SOURCECODE,		--PE: PE also returns ISNULL(tcfm.Code, 'missing') AS TRANSACTIONFLOWCODE (see PE Fields added below)
	CASE WHEN t.OpenCloseIndicator IN('OB','CS') THEN 1	
		ELSE 0 END										AS SyntheticOpenCloseFlag,
	A.SponsorCode,
	ISNULL((SELECT 1 FROM BETA.DBO.BETA_SECURITY_MSTR SM 
	WHERE SM.SECURITYNO = S.SECURITYNO AND MLPCODE IN ('I','B')), 0) AS REITFlag,
	1									AS UnitQuantity,		--PE: CAST(0 AS DECIMAL) AS UNITQUANTITY
	CAST(1 AS DECIMAL)					AS FACTOR,				
	0									AS DIRECTFEE,
	19									AS TRANSACTIONSOURCE,
	ISNULL(S.PMSecurityTypeID, 0)		AS SecurityTypeID,		
	''									AS BuySellInd,				
	NULL								AS Price,					
	0									AS WholeConversionFactor,	
	ISNULL(S.SecurityIdentifier,'')		AS SecurityIdentifier,		
	''									AS PMSecTypeDescription,
	''									AS AssetClassCode,
	ISNULL(T.TradeDate, T.AsOfDate)		AS ActivityAsOfDate,
	NULL								AS Cusip_Isin,	
	COALESCE(so.SecurityDescription,S.[Description],tdbo.TransactionDescription,tc.TransactionDesc,'') AS TransactionDescription, 
	''				AS SubsidiaryNo,
	''				AS AccountType,
	''				AS RanDAccountHld,
	''				AS Desc1,
	''				AS Desc2,
	Classification = 
		CASE 
			WHEN atm1.SrcTransPK IS NOT NULL THEN 2
			WHEN atm2.DestTransPK IS NOT NULL THEN 1
			WHEN ate.TransPK IS NOT NULL THEN 6			
			ELSE 0 -- 0 is unclassified
		END, 
	ISNULL(L.SSN,'') AS SSNTaxID,
	0				AS TransferFlag,
	0				AS JournalFlag,
	ISNULL(S.CUSIP,'') AS CUSIP,
	ISNULL(S.Symbol,'') AS Symbol,
	ISNULL(tcfm.Description, 'N/A') AS SourceCodeDescription,
	cast(t.TransactionID AS varchar(50)) AS TransactionPrimaryKey,
	'AI Synthetic'		AS DataSource,
	COALESCE(atm1.SrcTransPK, atm2.SrcTransPK) AS SrcTransPK,
	COALESCE(atm1.DestTransPK, atm2.DestTransPK) AS DestTransPK,
	COALESCE(atm1.SrcActLocCode, atm2.SrcActLocCode) AS SrcActLocCode,
	COALESCE(atm1.DestActLocCode, atm2.DestActLocCode) AS DestActLocCode,
	CAST(ISNULL(tcfm.InvestmentRedemptionFlag,0) AS INT) AS InvestmentRedemptionFlag,
	0 AS ChangeSign,
	1 AccountTypeCode,
	CAST(ISNULL(tcfm.TradeFlag, 0) AS INT) AS TradeFlag,
	tcfm.PSTransferFlag AS PSTransferFlag,
	tcfm.ExcludeFromClassification,
	ISNULL(S.SecurityNo, 0) as SecurityNo
From #AccountsAI L 
	JOIN (select 
					AccountId	,
					LPLAccountNo	,
					SponsorAccountNo	,
					SponsorCode

				from LPLCUSTOMER.DBO.ACCOUNTAIN  
				
				union all 
				
				select 
					AccountId	,
					LPLAccountNo	,
					SponsorAccountNo	,
					SponsorCode	

				from LPLCUSTOMER.DBO.ACCOUNTAI ) A ON L.ACCOUNTID = A.ACCOUNTID
	JOIN ALTERNATIVEINVESTMENTS.DBO.AccountSyntheticTransaction_Current T  ON A.SPONSORACCOUNTNO = T.COMPANYACCOUNTNO AND A.SPONSORCODE = T.COMPANYCD
	LEFT JOIN PortfolioManager.dbo.TransactionDirectBusinessOverride AS tdbo  
		ON tdbo.DataSource = 'AI Synthetic' AND tdbo.TransactionPrimaryKey = cast(t.TransactionID AS varchar(50))
	JOIN AlternativeInvestments.dbo.TransactionCode tc ON T.TransactionCd = tc.TransactionCd 
	LEFT JOIN LPLCUSTOMER.DBO.SecurityAI S  ON T.Cusip = S.Cusip
	LEFT JOIN LPLCustomer.dbo.SecurityOverride so  ON S.SecurityId = so.SecurityId
	LEFT JOIN PortfolioManager.dbo.TransactionCodeFlowMapping tcfm  ON ISNULL(NullIf(left(t.TranDetailCd, 6), ''), LEFT(t.TransactionCd,4)) = tcfm.code AND tcfm.Source = 'FanMail'
	left join PMPricing.dbo.HistoricalPriceAI hp  on s.SecurityID = hp.SecurityID AND t.AsofDate = hp.AsOfDate
	LEFT JOIN (SELECT atm.SrcTransPK, atm.SrcActLocCode, min(atm.DestTransPK) as DestTransPK, min(atm.DestActLocCode) as DestActLocCode
		FROM #AccountsAI acct join PortfolioManager.dbo.ActivityTransferMapping atm  
		ON acct.SponsorAccountNo = atm.SrcAccountNumber
		GROUP BY atm.SrcTransPK, atm.SrcActLocCode) atm1 
		 ON atm1.SrcTransPK = cast(t.TransactionID AS varchar(50)) and atm1.SrcActLocCode = l.AccountLocationCode
	LEFT JOIN (SELECT min(atm.SrcTransPK) AS SrcTransPK, min(atm.SrcActLocCode) AS SrcActLocCode, atm.DestTransPK, atm.DestActLocCode
		FROM #AccountsAI acct join PortfolioManager.dbo.ActivityTransferMapping atm  
		ON acct.SponsorAccountNo = atm.DestAccountNumber
		GROUP BY atm.DestTransPK, atm.DestActLocCode) atm2  
		 ON atm2.DestTransPK = cast(t.TransactionID AS varchar(50)) and atm2.DestActLocCode = l.AccountLocationCode
	LEFT JOIN PortfolioManager.dbo.ActivityTransferExclusions ate  ON ate.TransPK = cast(t.TransactionID AS varchar(50)) and ate.AccountLocationCode = l.AccountLocationCode
WHERE 
	ISNULL(T.TradeDate, T.AsOfDate) >= @COB_StartDate
	AND ISNULL(T.TradeDate, T.AsOfDate) <= L.AsOfDate
	AND NOT EXISTS ( 
		SELECT 1 FROM PORTFOLIOMANAGER.dbo.FfDirectBusiness W  
		WHERE w.DataSource='AI Synthetic' AND W.TransactionPrimaryKey=CAST(t.TransactionID AS VARCHAR(50)) AND W.Synthetic ='Y'
	)
 
--IF OBJECT_ID ('tempdb..#AccountsAI') IS NOT NULL D_ROP TABLE #AccountsAI
--IF OBJECT_ID ('tempdb..#csvAccountsAI') IS NOT NULL D_ROP TABLE #csvAccountsAI



