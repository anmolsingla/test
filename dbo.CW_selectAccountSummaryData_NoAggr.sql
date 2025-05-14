CREATE  PROCEDURE [dbo].[CW_selectAccountSummaryData_NoAggr]    
    @AccountListCSV Varchar(max),    
    @AccountNoListCSV varchar(max) = null,
    @FirmID int
AS      
      
/********************************************************************************************      
Stored Procedure: CW_selectAccountSummaryData_NoAggr      
---------------------------------------------------------------------------------------------      
Version : 1.0      
---------------------------------------------------------------------------------------------      
Purpose : Return LPL & NON LPL account summary data for a list of accounts.      
      
---------------------------------------------------------------------------------------------      
Revisions:      
1.0  01/03/2019 Steve Humpal Initial version      
1.1  02/03/2020 Robb Murdock Add RepId      
1.2  12/08/2020 Ayelet Soffer Avoid dropping temp tables.  Instead create & truncate.      
1.3  03/08/2010 Steve Humpal Added AccountNoListCSV for AccountContinuity      
1.4  08/04/2021 Robb Murdock Defect# 36800/37379 Use AccountBrowseDescription for AccountType      
         under certain conditions prescribed by Carrie Dover.      
1.5  09/27/2021 Ayelet Soffer Added the same logic Robb added on 08/04 under the      
         "Fetch LPL Account Summary Data" section      
1.6  10/11/2021 Steve Humpal Ensure unofficial assets have a description.      
     Robb Murdock Add RetirementStatus and Description work item #182252    
1.7  03/15/2023  Sunil Dhamale Add AdvisoryFeeType to get Account Type Tiered/Flat (CWCPM-3027)    
1.8  04/19/2023  Ratul Pramanick  Display Shell Account Nickname for Direct Business Accounts  (CWCPM-5785)   
1.9  03/19/2024  Shravan Pullagurla     Filter data by FirmID for Support..AccountClass table, added new input parameter FirmID
---------------------------------------------------------------------------------------------      
Unit Tests:      
 LPL Accounts:      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr] @AccountListCsv = '123123,4422244'      
      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr] @AccountListCsv = '', @AccountNoListCsv = '49074813, 67817703'      
      
 NON LPL Accounts:      
 IDM Account ==> 40000115 (DEVINT)      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr] @AccountListCsv = 40000115      
 AI Account ==> 18701170 (DEVINT)      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr] @AccountListCsv = 18701170      
 VA Account ==> 5187683 (DEVINT)      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr] @AccountListCsv = 41556467      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr] @AccountListCsv = 3506295      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr] @AccountListCsv = 7907788      
 exec portfoliomanager..PM_GetAccountData @AccountID = 17249334      
 MF Account ==> 4257586 (DEVINT)      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr] @AccountListCsv = 4257586      
 EDVA Account ==> 12098175 (DEVINT)      
 exec Reporting..[CW_selectAccountSummaryData_NoAggr]@AccountListCsv = 40019867      
      
exec Reporting..CW_getAccountSummaryData @AccountID = 18067606,@AccountLocationCode = 1,@StartDate = '01/01/2000',@EndDate = '02/01/2019'      
exec Reporting..CW_selectAccountSummaryData_NoAggr @AccountListCSV = '18067606'      
exec Reporting..CW_selectAccountRelatedMF @AccountListCsv = '18067606', @UserName = null      
      
select top 100 * from lplcustomer..account where accountid = 18070104      
exec Reporting..CW_selectAccountSummaryData_NoAggr @AccountListCSV = '18044972'      
      
---------------------------------------------------------------------------------------------      
********************************************************************************************/      
      
SET NOCOUNT ON      
SET Transaction Isolation Level Read Uncommitted      
      
IF OBJECT_ID ('tempdb..#Accounts') IS NOT NULL      
 BEGIN      
  TRUNCATE TABLE #Accounts      
 END      
ELSE      
 BEGIN      
  CREATE TABLE #Accounts (      
  AccountID INT,      
  AccountLocationCode INT,      
  LPLAccountNo VARCHAR(8),      
  RepId CHAR(4) NULL,      
  SponsorCode VARCHAR(4),      
  SponsorAccountNo VARCHAR(20),      
  SponsorType VARCHAR(1),      
  AsOfDate DateTime,      
  AccountType VARCHAR(250),      
  IRAType VARCHAR(250),      
  AccountClassCode VARCHAR(4)      
  )      
 END      
      
IF @AccountListCSV is not null AND LEN(@AccountListCSV) > 0      
BEGIN      
 /*******************************************************************      
 PARSE CSV ACCOUNT IDS INTO A TABLE      
 *******************************************************************/      
 -- AS 12/08/2020: Avoid dropping temp tables.  Instead create & truncate.      
 IF OBJECT_ID ('tempdb..#csvAccounts') IS NOT NULL      
  BEGIN      
   TRUNCATE TABLE #csvAccounts      
  END      
 ELSE      
  BEGIN      
      
  CREATE TABLE #csvAccounts      
  (      
  accountId int      
  )      
 END      
 INSERT INTO #csvAccounts(accountId)      
 SELECT Value from Reporting.dbo.udfParseCsv (@AccountListCSV) option(maxrecursion 0)      
      
 INSERT #Accounts (AccountID, AccountLocationCode, LPLAccountNo, RepId, SponsorCode, SponsorAccountNo, SponsorType, AsOfDate, AccountClassCode)      
 SELECT  DISTINCT    
  A.AccountId,      
  A.AccountLocationCode,      
  A.LPLAccountNo,      
  A.RepID,      
  A.SponsorCode,      
  A.SponsorAccountNo,      
  A.SponsorType,      
  AsOfDate = IsNull(aod.AsOfDate, A.AsOfDate),      
  A.AccountClassCode      
 FROM       
  --(SELECT cast(Value as int) as AccountId from Reporting.dbo.udfParseCsv (@AccountListCSV)) acctIds      
  #csvAccounts acctIds      
 JOIN       
  lplcustomer.dbo.account A      
   ON acctIds.AccountID = A.AccountId      
 LEFT JOIN       
  LPLCustomer.dbo.AsOfDates aod      
   ON a.SponsorCode = aod.SponsorCode AND a.SponsorType = aod.SponsorType      
END      
      
-- Support for AccountContinuity by being able to request accounts by AccountNo instead of AccountId      
-- NOTE: AccountContinuity is for LPL accounts only.      
IF @AccountNoListCSV is not null AND LEN(@AccountNoListCSV) > 0      
 BEGIN      
  /*******************************************************************      
  PARSE CSV ACCOUNT IDS INTO A TABLE      
  *******************************************************************/      
  -- AS 12/08/2020: Avoid dropping temp tables.  Instead create & truncate.      
  IF OBJECT_ID ('tempdb..#csvAccountNos') IS NOT NULL      
   BEGIN      
    TRUNCATE TABLE #csvAccountNos      
   END      
  ELSE      
   BEGIN      
      
   CREATE TABLE #csvAccountNos      
   (      
   accountNo char(8)      
   )      
  END      
  INSERT INTO #csvAccountNos(accountNo)      
  SELECT Value from Reporting.dbo.udfParseCsv (@AccountNoListCsv) option(maxrecursion 0)      
      
  INSERT #Accounts (AccountID, AccountLocationCode, LPLAccountNo, RepId, SponsorCode, SponsorAccountNo, SponsorType, AsOfDate, AccountClassCode)      
  SELECT  DISTINCT    
   A.AccountId,      
   A.AccountLocationCode,      
   A.LPLAccountNo,      
   A.RepID,      
   A.SponsorCode,      
   A.SponsorAccountNo,      
   A.SponsorType,      
   AsOfDate = IsNull(aod.AsOfDate, A.AsOfDate),      
   A.AccountClassCode      
  FROM       
   #csvAccountNos acctNos      
  JOIN       
   lplcustomer.dbo.AccountLPL A      
    ON acctNos.AccountNo = A.LPLAccountNo      
  LEFT JOIN       
   LPLCustomer.dbo.AsOfDates aod      
    ON a.SponsorCode = aod.SponsorCode AND a.SponsorType = aod.SponsorType      
 END      
      
DECLARE @COB_EndDate DATETIME      
DECLARE @MFNAsOfDate DATETIME      
      
SELECT @COB_EndDate = PortfolioManager.dbo.fn_GetPriceDate(GetDate())      
SELECT @MFNAsOfDate = AsOfDate FROM LPLCustomer.dbo.AsOfDates WHERE TableName = 'PositionMFN'      
      
-- make sure MFN is using MFNDate      
UPDATE #Accounts SET AsOfDate = @MFNAsOfDate      
FROM #Accounts acct WHERE acct.AccountLocationCode = 128      
      
--Update networked accounts with data from the shell account      
--Also update AccountClassCode for all nonLPL accounts      
update      
 #Accounts      
set      
      
      
 /* DEFECT 36800/37397 - 8/4/2021 Robb Murdock  Replaced the one line below with the more complex code that      
  checks for BAM InstitutionType of Z and the iraType.Type code not null.  If so begins coalese with       
  the preferred [IC].AccountBrowseDescription      
       
  --AccountType = COALESCE(iraType.Description, IC.[Description], 'Unknown'),  -- REPLACED WITH BELOW      
 */      
 AccountType = case       
     when       
     (      
      [BAM].InstitutionType ='Z'      
      and [iraType].TypeCode is null      
     ) then COALESCE([IC].AccountBrowseDescription, iraType.Description, IC.[Description], 'Unknown')      
     else      
     (       
      COALESCE(iraType.Description, IC.[Description], 'Unknown')      
     )      
     end,      
      
 /* END DEFECT 36800/37397   */      
      
      
 IRAType = COALESCE(iraType.Description, 'Unknown'),      
 AccountClassCode = COALESCE(NetworkA.AccountClassCode, LPLA.AccountClassCode)      
from      
 #Accounts A      
join      
 LPLCustomer.dbo.Account LPLA       
  on A.AccountId = LPLA.AccountID      
left join      
 LPLCustomer.dbo.Account NetworkA       
  on LPLA.NetworkedLPLAccountId = NetworkA.AccountId      
left join      
 Beta.dbo.BETA_IRA_MSTR BIM       
  on BIM.AccountNo = NetworkA.LPLAccountNo      
left join      
 beta.dbo.beta_acct_mstr BAM      
  on BAM.AccountNo = NetworkA.LPLAccountNo      
left join      
 Support.dbo.InstitutionCode IC      
  on BAM.InstitutionType = IC.InstitutionCode      
left join      
 Support.dbo.IRAType iraType       
  on BIM.IRAType = iraType.TypeCode      
where      
 A.AccountLocationCode NOT IN (1,2)      
      
/*******************************************************************************      
Fetch NON LPL Account Summary Data      
********************************************************************************/      
SELECT      
 CASE      
  WHEN ca.InvestmentObjectiveName = 'A - Income with Capital Preservation' THEN 'ICP'      
  WHEN ca.InvestmentObjectiveName = 'B - Income with Moderate Growth' THEN 'IMG'      
  WHEN ca.InvestmentObjectiveName = 'C - Growth with Income' THEN 'GWI'      
  WHEN ca.InvestmentObjectiveName = 'D - Growth' THEN 'G'      
  WHEN ca.InvestmentObjectiveName = 'E - Aggressive Growth' THEN 'AG'      
  WHEN ca.InvestmentObjectiveName = 'F - Trading' THEN 'T'      
  ELSE ''      
 END           AS IOCode,      
 ca.InvestmentObjectiveName     AS InvestmentObjectiveName ,      
 Null          AS SectionName,      
 Null          AS SectionSortOrder,      
 Null          AS AccountSortOrder,      
 A.AccountTitle        AS AccountTitle,      
 L.AccountID         AS AccountID,      
 L.AccountLocationCode      AS AccountLocationCode,      
 A.SponsorAccountNo       AS AccountNo,      
 ISNULL(A.LPLAccountNo,'')     AS LPLAccountNo,      
 A.SponsorAccountNo       AS SponsorAccountNo,      
 A.SponsorCode        AS SponsorCode,      
 A.AccountName        AS AccountName,      
 A.CUSIP          AS CUSIP, 
 /***CWCPM-5785 change start ***/  
Reporting.[dbo].[CW_udfGetNickName] (ISNULL(A.NetworkedLPLAccountID,0))      AS Nickname,      
 /***CWCPM-5785 change start ***/ 
 CASE       
  WHEN A.AccountLocationCode = 16 THEN ISNULL(AD.Description, 'Other Assets') -- unofficial update story CWCPM-3830      
  ELSE      
   CASE       
    WHEN AD.Description IS NOT NULL AND LEN(RTRIM(LTRIM(AD.Description))) > 0 THEN AD.Description      
    ELSE COALESCE(idm.ProductName,sp.SponsorName,'')      
   END      
 END           AS AccountClassName,      
 ISNULL(Ac1.[Name],'')      AS ACName,      
 CASE       
  WHEN AD.Description IS NOT NULL AND LEN(RTRIM(LTRIM(AD.Description))) > 0 THEN AD.Description      
  ELSE COALESCE(idm.ProductName,sp.SponsorName,'')      
 END           AS SponsorName,      
 CASE       
  WHEN A.IsClosed = 1 THEN 'Closed'      
  ELSE 'Open'      
 END           AS AccountStatus,      
 CASE       
  WHEN A.AccountLocationCode = 16 THEN T.Comments -- unofficial      
  ELSE AD.Notes      
 END           AS AccountNotes,      
 IsNull(peiv.IsEligible,0)     AS IsPerformanceEligible,      
 A.AccountOpenDate       AS AccountOpenDate,      
 CASE       
  WHEN L.AsOfDate < @COB_EndDate THEN L.AsOfDate      
  ELSE @COB_EndDate      
 END           AS EndPriceDate,      
 AC1.LPLCode         AS LPLCode,      
 ISNULL(A.NetworkedLPLAccountID,0)   AS NetworkedLPLAccountID,      
 A.SSNTaxID         AS SSNTaxID,      
 ISNULL(AC1.AccountType,'')     AS BrokerageAdvisory,      
 CASE       
  WHEN COALESCE(D.PerformanceStartDate,A.AccountOpenDate) <peiv.PID THEN peiv.PID      
  ELSE COALESCE(D.PerformanceStartDate,A.AccountOpenDate)      
 END           AS InceptionDate,      
 D.PIDUpdateSource       AS PIDUpdateSource,      
 D.PerformanceStartDate      AS PID,      
 peiv.PID         AS PED,      
 COALESCE(D.PerformanceEndDate,A.AccountClosedDate) AS ClosedDate,      
 AL.AccountLocationName      AS AccountLocationName,      
 A.TotalAccountValue       AS TotalAccountValue,      
 COALESCE(VACS.ContractStatusDescription,VACS2.ContractStatusDescription,'') AS ContractStatus,      
 COALESCE(OVD.Owner,VAA.Owner1,'')   AS [Owner],      
 COALESCE(OVD.Annuitant,VAA.Annuitant1,'') AS Annuitant,      
 CASE      
  WHEN RTRIM(COALESCE(OVD.ContractStatus,VAD.ContractStatus,'')) IN('SC','SE','SI','SU') THEN 'Yes'      
  ELSE 'No'      
 END           AS ContractInSurrender,      
 COALESCE(OVD.OutOfSurrenderDate,VAD.OutOfSurrenderDate) AS OutOfSurrenderDate,      
 COALESCE(OVD.GuaranteedMinDeathBenefit,VAD.GuaranteedMinDeathBenefit) AS MinGuaranteedDeathBenefit,      
 COALESCE(OVD.DeathBenefit,VAD.DeathBenefit) AS DeathBenefit,      
 COALESCE(OVD.CostBasis,VAD.CostBasis)  AS CostBasis,      
 COALESCE(OVD.TransferOnDeath,VAD.TransferOnDeath) AS TransferOnDeath,      
 COALESCE(OVD.ReqMinDist,VAD.ReqMinDist)  AS MinRqdDistribution,--this should no longer be used; leave for B/C      
 COALESCE(OVD.ReqMinDist,VAD.ReqMinDist)  AS IRAMktValueYE,      
 VAD.PartyDOB        AS BirthDate,      
 RTRIM(VAD.IRSTaxCode)      AS IRSTaxCode,      
 COALESCE(OVD.ProjGuarIncomeBaseAmt,VAD.ProjGuarIncomeBaseAmt) As MinGuaranteedIncomeBenefit,      
 VAA.ContractValue       AS ContractValue,      
 CASE      
  WHEN AC1.InvestmentRetirement = 'I' THEN 'Non-Retirement'      
  WHEN AC1.InvestmentRetirement = 'R' THEN 'Retirement'      
  ELSE       
   case       
    when T.InvestmentRetirement = 'I' then 'Non-Retirement'      
    when T.InvestmentRetirement = 'R' then 'Retirement'      
    else 'Unclassified'       
   end      
 END           AS InvestmentRetirement,      
 CASE      
  WHEN AC1.AccountType = 'A' THEN 'Advisory'      
  WHEN AC1.AccountType = 'B' THEN 'Brokerage'      
  ELSE 'Unclassified'       
 END           AS BillingStyle,      
 A.SponsorAccountNo       AS AccountNumber,      
 ISNULL(sp.SponsorName, 'Other Sponsor')  AS CompanyName,      
 ISNULL(L.AccountType, 'Unknown')   AS AccountType,      
 ISNULL(L.IRAType, 'Unknown')    AS IRAType,      
 c.ClientName        AS ClientName,    
 /***CWCPM-3027 change start ***/    
 FEE.AdvisoryFeeType  AS AdvisoryFeeType,      
 /***CWCPM-3027 change end ***/    
 FEE.ClientFeePercent      AS AdvisorFeePercent,      
 CAST(0 AS BIT)        AS IsRetirementPartnersAccount,      
 A.RepId,      
 isnull(A.InvestmentObjectiveCode,'')  as InvestmentObjectiveCode,      
 ''           as OldAccountNo,      
 isnull([AD].Description,'')     as Description      
      
FROM       
 LPLCustomer.dbo.Account A       
JOIN       
 #Accounts L       
  on A.AccountID = L.AccountID       
   AND A.AccountLocationCode = L.AccountLocationCode      
   AND L.AccountLocationCode NOT IN (1, 2)      
LEFT JOIN       
 lplcustomer..MFVASponsor sp      
  ON sp.SponsorCode = a.sponsorcode AND sp.SponsorType = a.SponsorType      
LEFT JOIN       
 Support..AccountClass AC1       
  ON Ac1.LPLCode = L.AccountClassCode
  and AC1.FirmId = @FirmId
LEFT JOIN       
 portfoliomanager..UnofficialAccount T       
  ON T.ID = L.AccountID      
LEFT JOIN       
 PortfolioManager..AccountNicknames an       
  ON a.LplAccountNo = an.lplaccountnumber      
LEFT JOIN       
 PortfolioManager..AccountDetails AD       
  ON AD.AccountID = L.AccountID      
LEFT JOIN       
 LPLCustomer..AccountIDM idm       
  ON L.AccountID = idm.AccountID      
LEFT JOIN       
 LPLCustomer..AccountPerformanceDates D       
  ON L.AccountID = D.AccountID and L.AccountLocationCode = D.AccountLocationCode      
LEFT JOIN       
 PortfolioManager..PerformanceEligibleInfo_View peiv       
  ON peiv.AccountID = L.AccountID      
LEFT JOIN       
 LPLCustomer..AccountLocation AL       
  ON A.AccountLocationCode = AL.AccountLocationCode      
LEFT JOIN       
 DirectBusiness..VAAccounts VAA      
  ON A.SponsorAccountNo = VAA.ContractNo AND A.SponsorCode = VAA.InsurerID      
LEFT JOIN       
 DirectBusiness..VAAccounts_AdditionalData VAD ON VAA.Contractno = VAD.ContractNo AND VAA.InsurerID = VAD.InsurerID      
LEFT JOIN       
 PortfolioManager..VARiderOverride OVD       
  ON A.SponsorAccountNo = OVD.SponsorAccountNo AND A.SponsorCode = OVD.SponsorCode      
LEFT JOIN       
 DirectBusiness..VAContractStatus VACS       
  ON OVD.ContractStatus = VACS.ContractStatusCode      
LEFT JOIN       
 DirectBusiness..VAContractStatus VACS2      
  ON VAD.ContractStatus = VACS2.ContractStatusCode      
LEFT JOIN       
 LPLCustomer..ClientAccounts ca       
  ON a.AccountId = ca.AccountId AND a.AccountLocationCode = ca.AccountLocationCode      
LEFT JOIN       
 LPLCustomer..Client c       
  on ca.ClientId = c.ClientId      
LEFT JOIN       
 LPLCustomer..AccountAdvisoryInfo FEE       
  on A.AccountID = FEE.AccountId      
      
UNION ALL      
/*******************************************************************************      
Fetch LPL Account Summary Data      
********************************************************************************/      
SELECT      
      
 CASE      
  WHEN ca.InvestmentObjectiveName = 'A - Income with Capital Preservation' THEN 'ICP'      
  WHEN ca.InvestmentObjectiveName = 'B - Income with Moderate Growth' THEN 'IMG'      
  WHEN ca.InvestmentObjectiveName = 'C - Growth with Income' THEN 'GWI'      
  WHEN ca.InvestmentObjectiveName = 'D - Growth' THEN 'G'      
  WHEN ca.InvestmentObjectiveName = 'E - Aggressive Growth' THEN 'AG'      
  WHEN ca.InvestmentObjectiveName = 'F - Trading' THEN 'T'      
  ELSE ''       
 END AS IOCode,      
 ca.InvestmentObjectiveName ,      
 Null          as SectionName,      
 Null          as SectionSortOrder,      
 Null          as AccountSortOrder,      
 A.AccountTitle        AS AccountTitle,      
 L.AccountID,      
 L.AccountLocationCode,      
 L.LPLAccountNo        AS AccountNo,      
 L.LPLAccountNo,      
 ''           AS SponsorAccountNo,      
 ''           AS SponsorCode,       
 A.AccountName,      
 A.CUSIP          AS CUSIP,      
 AN.NickName         AS Nickname,      
 CASE       
  WHEN AD.Description IS NOT NULL AND LEN(RTRIM(LTRIM(AD.Description))) > 0 THEN AD.Description       
  ELSE ISNULL(Ac1.[Name],'')       
 END           AS AccountClassName,      
 ISNULL(Ac1.[Name],'')      AS ACName,      
 ''           AS SponsorName,      
 CASE       
  WHEN A.IsClosed = 1 THEN 'Closed'      
  ELSE 'Open'      
 END           AS AccountStatus,      
 AD.Notes         AS AccountNotes,      
 1           AS IsPerformanceEligible,      
 A.AccountOpenDate,      
 @COB_EndDate        AS EndPriceDate,      
 AC1.LPLCode,      
 0           AS NetworkedLPLAccountID,      
 A.SSNTaxId,      
 ac1.AccountType        AS BrokerageAdvisory,      
 ISNULL(D.PerformanceStartDate, A.AccountOpenDate) AS InceptionDate,      
 D.PIDUpdateSource       AS PIDUpdateSource,      
 D.PerformanceStartDate      AS PID,      
 NULL          AS PED,      
 ISNULL(D.PerformanceEndDate, A.AccountClosedDate) AS ClosedDate,      
 NULL          AS AccountLocationName,      
 NULL          AS TotalAccountValue,      
 NULL          AS ContractStatus,      
 NULL          AS [Owner],      
 NULL          AS Annuitant,      
 NULL          AS ContractInSurrender,      
 NULL          AS OutOfSurrenderDate,      
 NULL          AS MinGuaranteedDeathBenefit,      
 NULL          AS DeathBenefit,      
 NULL          AS CostBasis,      
 NULL          AS TransferOnDeath,      
 NULL          AS MinRqdDistribution, --this should no longer be used; leave for B/C      
 BIM.IRAMktValueYE       AS IRAMktValueYE,      
 A.PrimaryBirthDate       AS BirthDate,      
 NULL          AS IRSTaxCode,      
 NULL          AS MinGuaranteedIncomeBenefit,      
 0           AS ContractValue,      
 CASE      
  WHEN AC1.InvestmentRetirement = 'I' THEN 'Non-Retirement'      
  WHEN AC1.InvestmentRetirement = 'R' THEN 'Retirement'      
  ELSE 'Unclassified'        
 END           AS InvestmentRetirement,      
 CASE      
  WHEN AC1.AccountType = 'A' THEN 'Advisory'      
  WHEN AC1.AccountType = 'B' THEN 'Brokerage'      
  ELSE 'Unclassified'       
 END           AS BillingStyle,      
 L.LPLAccountNo        AS AccountNumber,      
 'LPL Financial'        AS CompanyName,      
      
 /* DEFECT 36800/37397 - 9/27/2021 Ayelet Soffer  Replaced the one line below with the more complex code that      
 checks for BAM InstitutionType of Z and the iraType.Type code not null.  If so begins coalese with       
 the preferred [IC].AccountBrowseDescription      
       
 --AccountType = COALESCE(iraType.Description, IC.[Description], 'Unknown'),  -- REPLACED WITH BELOW      
 */      
 AccountType = case       
    when       
    (      
     [BAM].InstitutionType ='Z'      
     and [iraType].TypeCode is null      
    ) then COALESCE([IC].AccountBrowseDescription, iraType.Description, IC.[Description], 'Unknown')      
    else      
    (       
     COALESCE(iraType.Description, IC.[Description], 'Unknown')      
    )      
    end,      
      
 /* END DEFECT 36800/37397   */      
       
 COALESCE(iraType.Description, 'Unknown') AS IRAType,      
 c.ClientName,     
 /***CWCPM-3027 change start ***/    
 FEE.AdvisoryFeeType,    
 /***CWCPM-3027 change end ***/    
 FEE.ClientFeePercent,      
 CAST(CASE WHEN (nrp.AccountNo IS NOT NULL) THEN 1 ELSE 0 END AS BIT) AS IsRetirementPartnersAccount,      
 A.RepId,      
 isnull(A.InvestmentObjectiveCode,'')  as InvestmentObjectiveCode,      
 bam.OldAccountNo,      
 isnull([AD].Description,'')     as Description      
      
FROM       
 LPLCustomer.dbo.Account A       
JOIN       
 #Accounts L       
  ON L.AccountID = A.AccountID       
   AND L.AccountLocationCode = A.AccountLocationCode      
   AND L.AccountLocationCode IN (1, 2)      
LEFT JOIN       
 Support.dbo.AccountClass AC1      
  ON Ac1.LPLCode= L.AccountClassCode 
  and AC1.FirmId = @FirmId
LEFT JOIN       
 PortfolioManager..AccountDetails AD       
  ON AD.AccountID = L.AccountID      
LEFT JOIN       
 LPLCustomer..AccountPerformanceDates D       
  ON L.AccountID = D.AccountID and L.AccountLocationCode = D.AccountLocationCode      
LEFT JOIN       
 Beta.dbo.BETA_IRA_MSTR BIM       
  ON BIM.AccountNo = A.LPLAccountNo      
LEFT JOIN       
 beta.dbo.beta_acct_mstr BAM       
  ON BAM.AccountNo = A.LPLAccountNo      
LEFT JOIN       
 Support.dbo.InstitutionCode IC       
  on BAM.InstitutionType = IC.InstitutionCode      
LEFT JOIN       
 Support.dbo.IRAType iraType       
  ON BIM.IRAType = iraType.TypeCode      
LEFT JOIN       
 LPLCustomer..ClientAccounts ca       
  ON a.AccountId = ca.AccountId AND a.AccountLocationCode = ca.AccountLocationCode      
LEFT JOIN       
 LPLCustomer..Client c       
  on ca.ClientId = c.ClientId      
LEFT JOIN       
 Beta.dbo.BETA_ACCT_MSTR_EXTENDED bame       
  ON A.LPLAccountNo = bame.AccountNo       
   AND bame.SuppFieldName = 'RET PLAN'       
   AND bame.SuppFieldValue = 'Y'      
LEFT JOIN       
 NRPRetirementPlans.dbo.AccountSummary nrp       
  ON bame.AccountNo = nrp.AccountNo      
LEFT JOIN       
 LPLCustomer..AccountAdvisoryInfo FEE       
  on A.AccountID = FEE.AccountId      
LEFT JOIN       
 PortfolioManager.dbo.AccountNicknames AN       
  ON A.LPLAccountNo = AN.LPLAccountNumber      
      
-- AS 12/08/2020: Avoid dropping temp tables.  Instead create & truncate.      
--IF OBJECT_ID ('tempdb..#Accounts') IS NOT NULL      
--T_RUNCATE TABLE #Accounts      
      
--IF OBJECT_ID ('tempdb..#csvAccounts') IS NOT NULL      
--T_RUNCATE TABLE #csvAccounts