USE [DBA]
GO
/****** Object:  StoredProcedure [dbo].[MNT_KillAllProcesses]    Script Date: 1/19/2023 8:06:00 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER  PROCEDURE [dbo].[MNT_KillAllProcesses] 
     @pDbName varchar (100)=NULL /*database where we will kill processes. If NULL-we will attempt to kill processes in all DBs*/
,    @pUserName varchar (100)=NULL /*user in a GIVEN database or in all databases where such a user name exists, whose processes we are going to kill. If NULL-kill all processes. */
AS

SET NOCOUNT ON
	
DECLARE @p_id smallint
DECLARE @dbid smallint
DECLARE @dbname varchar(100) 
DECLARE @exec_str varchar (255)  
DECLARE @error_str varchar (255)  

IF NOT EXISTS (SELECT * FROM master.dbo.sysdatabases where name=ltrim(rtrim(@pDbName)) or @pDbName is NULL)
BEGIN
     Set @error_str='No database '+ltrim(rtrim(@pDbName)) +' found.'
	 Raiserror(@error_str, 16,1)
	 RETURN-1
END

Create Table ##DbUsers(
     dbid    smallint
,    uid     smallint
)

If @pUserName is not null
    BEGIN        --Search for a user in all databases or a given one
        DECLARE curDbUsers CURSOR FOR  
        SELECT dbid,name  FROM master.dbo.sysdatabases where name=ltrim(rtrim(@pDbName)) or @pDbName is NULL
        OPEN curDbUsers   
        FETCH NEXT FROM curDbUsers INTO @dbid,@dbname  
        WHILE @@FETCH_STATUS = 0   
        BEGIN  
            SELECT @exec_str='Set quoted_identifier off
                INSERT ##DbUsers SELECT '+cast(@dbid as char)+', uid FROM '+@dbname+'.dbo.sysusers
                WHERE name="'+ltrim(rtrim(@pUserName))+'"' 
            EXEC (@exec_str)  
            FETCH NEXT FROM curDbUsers INTO @dbid,@dbname   
        END  
        CLOSE curDbUsers  
        DEALLOCATE curDbUsers
        If not exists(Select * from ##DbUsers)
            BEGIN
                Set @error_str='No user '+ltrim(rtrim(@pUserName)) +' found.'
                DROP TABLE ##DbUsers  
                Raiserror(@error_str, 16,1)
                RETURN-1
            END
    END 
ELSE --IF  @pUserName is null
    BEGIN
        INSERT ##DbUsers SELECT ISNULL(db_id(ltrim(rtrim(@pDbName))),-911),-911
    END

--select * from ##dbUsers

DECLARE curAllProc CURSOR FOR  
SELECT spid,sp.dbid FROM master.dbo.sysprocesses sp   
INNER JOIN ##DbUsers t ON (sp.dbid = t.dbid or t.dbid=-911) and (sp.uid=t.uid or t.uid=-911)
OPEN curAllProc   
FETCH NEXT FROM curAllProc INTO @p_id, @dbid 
  
WHILE @@FETCH_STATUS = 0   
    BEGIN    
        SELECT @exec_str = 'KILL '+ Convert(varchar,@p_id)+ ' checkpoint'  
        SELECT @error_str = 'Attempting to kill process '+Convert(varchar,@p_id)+' in database '+db_name(@dbid)   
        RAISERROR (@error_str,10,1)with log  
        EXEC (@exec_str)  
        FETCH NEXT FROM curAllProc INTO @p_id, @dbid 
    END  

CLOSE curAllProc  
DEALLOCATE curAllProc
DROP TABLE ##DbUsers 
SET NOCOUNT OFF 



