USE [OSJSupervision]
GO

/****** Object:  StoredProcedure [dbo].[Incomplete_Master]    Script Date: 3/22/2024 4:36:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE     PROCEDURE [dbo].[Incomplete_Master]           
(        
 @Tenantid int        
)                                       
AS                                          
BEGIN                                          
 /*==============================================================================                                                          
Project: OSJ Review Tool - Rewrite                                                         
------------------------------------------------------------------------------                                                          
Description:                                                          
----------------------------------------------------------------------------                                                          
Return Type:      
Comments:   
04/26/2016 Sai Amirineni Adding new column ReasonForCOAFlag.      
03/13/2017 Sai Amirineni Adding new SP call to load the ReviewITem_SharedRepID table  
08/13/2018 Sai Amirineni Adding new SP call to auto approve non flagged Advisory accounts.    
02/25/2019 Sai amirineni Adding new SP call to auto approve OBA Review tasks.                                 
==============================================================================*/                                          
 SET NOCOUNT ON                                          
                                          
 DECLARE @err INT,                                          
  @ErrorMessage VARCHAR(1024),                                          
  @SPName SYSNAME,                                          
  @DISErrorNumber INT                                          
                                         
                                          
 IF NOT EXISTS (                                          
   SELECT *                                          
   FROM tempdb.dbo.sysobjects                                          
   WHERE id = object_id(N'tempdb.dbo.#StoredProcProgressMessages')                                          
   )                                          
  CREATE TABLE #StoredProcProgressMessages (                                          
   MessageTime DATETIME,                                          
   ProcedureName VARCHAR(256),                                          
   Message VARCHAR(2048),                                          
   ErrorCode INT                                          
   )                                          
                                          
 INSERT INTO #StoredProcProgressMessages (                                          
  MessageTime,                                          
  ProcedureName,                                          
  Message,                                          
  ErrorCode                                          
  )                                          
 VALUES (                                          
  Getdate(),                                          
  @SPName,                                          
  'Start Procedure',                                          
  - 1                                          
  )                                          
                                          
 SET @DISErrorNumber = - 1                                          
                                          
                               
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[IncompleteTaskList]') AND type in (N'U'))          
DROP TABLE [dbo].[IncompleteTaskList]          
          
          
          
CREATE TABLE [dbo].[InCompleteTaskList](                
 [RowNumber] [int] IDENTITY(1,1) NOT NULL,                
 [TaskId] [int] NULL,                
 [TaskTypeId] [int] NULL,                
 [TaskTypeDescription] [varchar](64) NULL,                
 [CompletionDate] [datetime] NULL,                
 [DueDate] [datetime] NULL,                
 [Notes] [varchar](4000) NULL,                
 [Status] [varchar](40) NULL,                
 [ClientName] [varchar](81) NULL,                 
 [BranchID] [char](4) NULL,                
 [RepId] [char](4) NULL,                
 [OSJREPID] [char](4) NULL,                
 [MasterRepId] [char](4) NULL,                
 [RepName] [varchar](30) NULL,                
 [AccountID] [int] NULL,                
 [LPLCustomerAccountID] [int] NULL,                
 [AccountNumber] [char](8) NULL,                
 [StatusId] [int] NULL,                
 [DisplayGroup] [smallint] NULL,      
 [CreateDate] [datetime] NULL,                
 [ReviewedBy] [char](4) NULL,                
 [DisplayText] [varchar](50) NULL,                
 [Name1] [varchar](30) NULL,                
 [Name2] [varchar](30) NULL,                
 [Name3] [varchar](30) NULL,                
 [Name4] [varchar](30) NULL,                
 [Name5] [varchar](30) NULL,                
 [Name6] [varchar](30) NULL,                
 [AccountName] [varchar](40) NULL,                
 [StreetAddress1] [varchar](80) NULL,                
 [StreetAddress2] [varchar](80) NULL,                
 [City] [varchar](30) NULL,                
 [State] [char](2) NULL,                
 [Zip] [char](9) NULL,                
 [ClientPhone] [char](11) NULL,                
 [SSN] [char](9) NULL,                
 [DOB] [datetime] NULL,                
 [GroupID] [int] NULL,                
 [IsSSN] [bit] NULL,                
 [IsHighRisk] [bit] NULL,                
 [HighRiskConditions] [varchar](4000) NULL,                
 [ApprovalStatus] [varchar](25) NULL,                
 [RequiresApproval] [bit] NULL,                
 [ownTask] [bit] NULL,                
 [DataMissing] [bit] NULL,                
 [ComCount] [int] NULL,                
 [ComStatus] [varchar](20) NULL,                
 [CommunicationStatusID] [int] NULL,                
 [CommunicationID] [int] NULL,                
 [DPId] [char](4) NULL,                
 [TenantID] [int] NULL,  
 [ReasonForCOAFlag] [VARCHAR] (4000) NULL              
              
) ON [PRIMARY]                 
          
          
  SELECT @SPName = 'Incomplete_Master'       
 If(@tenantid = 1) Begin     
     
        
                                    
  Print 'Started Step 1 , Loading all columns from ReviewItem/ReviewItemType/ReviewStatus'                                       
  SELECT @SPName = 'OSJ_GetReviewItemList_Incomplete_ServerPaging_Filtering_Internal'                                          
  EXEC OSJ_GetReviewItemList_Incomplete_ServerPaging_Filtering_Internal                                    
  Print 'Completed Step 1'     
    
  Print 'Started Step 2 , Loading all columns for Investment Product Switch'                                       
  SELECT @SPName = 'OSJ_GetReviewItemList_Incomplete_ServerPaging_Filtering_83'                                          
  EXEC OSJ_GetReviewItemList_Incomplete_ServerPaging_Filtering_83                                    
  Print 'Completed Step 2'     
  
   Print 'Started Step 2 , Loading all columns for Investment Product Switch'                                       
  SELECT @SPName = 'OSJ_GetReviewItemList_Incomplete_ServerPaging_Filtering_Customer_83'                                          
  EXEC OSJ_GetReviewItemList_Incomplete_ServerPaging_Filtering_Customer_83                                    
  Print 'Completed Step 2'     
  
  Print 'Started last Step, Creating Index'                                           
  SELECT @SPName = 'Create_InCompleteTaskList_Index'                                          
  EXEC Create_InCompleteTaskList_Index                                         
  Print 'Completed Last'    
               
  Print 'Started Step 3, Loading Communications Columns'                                      
  SELECT @SPName = 'update_Communication_IncompleteTaskList'                                          
  EXEC update_Communication_IncompleteTaskList                                          
  Print 'Completed Step 3'                                        
                                      
  Print 'Started Step 4, Loading all the Groupinfo and LPLAccount Columns'                                         
  SELECT @SPName = 'Update_ReviewAccountno_BetaCoumns'                                      
  EXEC Update_ReviewAccountno_BetaCoumns                                          
  Print 'Completed Step 4'                                 
                                      
                                          
  Print 'Started Step 5, Loading all the Groupinfo and LPLAccount Columns'                                         
  SELECT @SPName = 'update_GroupInfo_AccountLPL_columns'                                      
  EXEC update_GroupInfo_AccountLPL_columns                                          
  Print 'Completed Step 5'      
        
  Print 'Started Step 6, Loading HighRisk Columns'                                      
  SELECT @SPName = 'update_isHighRisk_IncompleteTaskList'                                          
  EXEC update_isHighRisk_IncompleteTaskList                                          
  Print 'Completed Step 6'                                        
                                                                   
                                      
  Print 'Started Step 7, Updating the Notes columns'                                           
  SELECT @SPName = 'update_Notes'                                          
  EXEC update_Notes                                         
  Print 'Completed Step 7'                                         
                                      
                                      
  Print 'Started Step 8, Updating RequiresApproval'              
  SELECT @SPName = 'update_RequiresApproval'                                          
  EXEC update_RequiresApproval                                         
  Print 'Completed Step 8'                       
                      
  Print 'Started Step 9, Updating DataMissing'                                           
  SELECT @SPName = 'update_dataMissing'                                          
  EXEC update_dataMissing                                         
  Print 'Completed Step 9'                       
          
  Print 'Started Step 10, Loading Communications Columns'                        
  SELECT @SPName = 'update_Communication_IncompleteTaskList'                            
  EXEC update_Communication_IncompleteTaskList_83                            
  Print 'Completed Step 10'                          
                       
  Print 'Started Step 11, Loading all the Groupinfo and LPLAccount Columns'                           
  SELECT @SPName = 'Update_ReviewAccountno_BetaCoumns'                        
  EXEC Update_ReviewAccountno_BetaCoumns_83                           
  Print 'Completed Step 11'                        
                       
                           
  Print 'Started Step 12, Loading all the Groupinfo and LPLAccount Columns'                           
  SELECT @SPName = 'update_GroupInfo_AccountLPL_columns'                        
  EXEC update_GroupInfo_AccountLPL_columns_83                            
  Print 'Completed Step 12'                        
                       
  Print 'Started Step 13, Updating the Notes columns'                             
  SELECT @SPName = 'update_Notes'                            
  EXEC update_Notes_83                           
  Print 'Completed Step 13'   
    
  Print 'Started Step 14, Updating the ReasonForCOAFlag columns'                             
  SELECT @SPName = 'update_ReasonForCOAFlag'                            
  EXEC update_ReasonForCOAFlag                           
  Print 'Completed Step 14'   
    
    Print 'Started Step 15, Populating the ReviewITem_SharedRepID table'                             
  SELECT @SPName = 'OSJ_PopulateReviewITem_SharedRep'                            
  EXEC OSJ_PopulateReviewITem_SharedRep                          
  Print 'Completed Step 15'   
  
 /* Updating the OSJRepId column with the OSJ_Mgr_id of the rep from the DCDMNT_MTL_REP table for the rep on thetask if OSJRepid column is null*/  
Print 'Started Step 16, Populating the missing OSJRepID column table'   
SELECT @SPName = 'update_MissingOSJRepId'    
EXEC OSJSupervision.dbo.update_MissingOSJRepId  
 Print 'Completed Step 16'   
  
  
Print 'Started Step 17, Updating Task Description for MFO Tasks'   
SELECT @SPName = 'update_MFOTask_IncompleteTaskList'    
EXEC OSJSupervision.dbo.update_MFOTask_IncompleteTaskList  
 Print 'Completed Step 17'    
   
    
  Print 'Started Step 18, Auto approving Non flagged Advisory Accounts'                             
  SELECT @SPName = 'OSJ_AutoApproveNonFlaggedAdvisoryTasks'                            
  EXEC OSJ_AutoApproveNonFlaggedAdvisoryTasks                          
  Print 'Completed Step 18'   
    
  Print 'Started Step 19, OSJ_AutoApproveOBAReviewTasks'                             
  SELECT @SPName = 'OSJ_AutoApproveOBAReviewTasks'                            
  EXEC OSJ_AutoApproveOBAReviewTasks                         
  Print 'Completed Step 19'   
    
  Print 'Started Step 20, OSJ_Update_Communication'                             
  SELECT @SPName = 'OSJ_Update_Communication'                            
  EXEC OSJ_Update_Communication                         
  Print 'Completed Step 20'   
    
  update tasklog                     
  set CheckEndDate = getdate(),Tenantid = @Tenantid                  
  where   TaskName = 'IncompleteMaster'                                            
 End         
 Else If (@tenantid = 3)    
     
 BEgin    
     
    
      
  Print 'Started Step 1 , Loading all columns from ReviewItem/ReviewItemType/ReviewStatus'                                             
  SELECT @SPName = 'OSJ_GetReviewItemList_Incomplete_ServerPaging_Filtering_Internal_AXA'                                                
  EXEC OSJ_GetReviewItemList_Incomplete_ServerPaging_Filtering_Internal_AXA                                                
  Print 'Completed Step 1'    

   
  Print 'Started last Step, Creating Index'                                           
  SELECT @SPName = 'Create_InCompleteTaskList_Index'                                          
  EXEC Create_InCompleteTaskList_Index                                         
  Print 'Completed Last'    
         
     Print 'Started Step 2, Loading all the Groupinfo and LPLAccount Columns'                                         
  SELECT @SPName = 'Update_ReviewAccountno_BetaCoumns'                                      
  EXEC Update_ReviewAccountno_BetaCoumns                                          
  Print 'Completed Step 2'     
      
  Print 'Started Step 3, Loading all the Groupinfo and LPLAccount Columns'                                         
  SELECT @SPName = 'update_GroupInfo_AccountLPL_columns'                                      
  EXEC update_GroupInfo_AccountLPL_columns                                          
  Print 'Completed Step 3'      
      
  --Print 'Started Step 4, Loading HighRisk Columns'                                            
  --SELECT @SPName = 'update_isHighRisk_IncompleteTaskList_AXA'                                                
  --EXEC update_isHighRisk_IncompleteTaskList_AXA                                                
  --   Print 'Completed Step 4'     
         
     Print 'Started Step 4, Updating the Notes columns'                                           
  SELECT @SPName = 'update_Notes'                                          
  EXEC update_Notes                                         
  Print 'Completed Step 4'       
      
  Print 'Started Step 5, Updating RequiresApproval'                                           
  SELECT @SPName = 'update_RequiresApproval'                                          
  EXEC update_RequiresApproval                                         
  Print 'Completed Step 5'     
      
  --Print 'Started Step 7, Updating DataMissing'                                           
  --SELECT @SPName = 'update_dataMissing'                                          
  --EXEC update_dataMissing                                         
  --Print 'Completed Step 7'   
    
   Print 'Started Step 6, Updating the ReasonForCOAFlag columns'                             
  SELECT @SPName = 'update_ReasonForCOAFlag'                            
  EXEC update_ReasonForCOAFlag                           
  Print 'Completed Step 6'   
      
 Print 'Started Step 7, Updating Task Description for MFO Tasks'   
 SELECT @SPName = 'update_MFOTask_IncompleteTaskList'    
 EXEC OSJSupervision.dbo.update_MFOTask_IncompleteTaskList  
 Print 'Completed Step 7'    
  
      
 Print 'Started Step 9, Updating NAO Accountno and Names'                                         
 SELECT @SPName = 'Update_NAO_AccountNo_Name_Adhoc_AXA'                                       
 EXEC Update_NAO_AccountNo_Name_Adhoc_AXA 96 --AXA Naar Only                                      
 Print 'Completed Step 9 , Update_NAO_AccountNo_Name_Adhoc_AXA'  
 
  Print 'Started Step 10, Updating NAO Accountno and Names'                                         
 SELECT @SPName = 'Update_NAO_AccountNo_Name_Adhoc_AXA'                                       
 EXEC Update_NAO_AccountNo_Name_Adhoc_AXA 97 --Account Suitability Only                                      
 Print 'Completed Step 10 , Update_NAO_AccountNo_Name_Adhoc_AXA' 

 Print 'Started Step 11, Updating Display Text Column'                                         
 SELECT @SPName = 'OSJ_UpdateDisplayText_AXA'                                       
 EXEC OSJ_UpdateDisplayText_AXA --CIP , Account Review                                      
 Print 'Completed Step 11 , OSJ_UpdateDisplayText_AXA'   
     
  
  update tasklog                     
  set CheckEndDate = getdate(),Tenantid = @Tenantid                  
  where   TaskName = 'IncompleteMaster_AXA'     
 End       
     
                        
End           
GO


