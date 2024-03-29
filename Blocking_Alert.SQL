USE [DBA]
GO
/****** Object:  StoredProcedure [dbo].[spr_Monitor_Blocking]    Script Date: 1/2/2023 12:26:36 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER Proc [dbo].[spr_Monitor_Blocking]
as

Declare @C as varchar(200) 
Set @C = 'Company Name'

DECLARE @vRecipients AS VARCHAR (MAX)
DECLARE @vSubject AS NVARCHAR (255)
Declare @D as Varchar(200) Set @D = (CONVERT(CHAR(10), GETDATE(), 101))
Declare @RC1 as int
Declare @RC2 as int
Declare @Run as Varchar(20)

Begin
	DROP TABLE IF EXISTS #sp_who2
	CREATE TABLE #sp_who2 (SPID INT, Status VARCHAR(255),
		  Login  VARCHAR(255), HostName  VARCHAR(255),
		  BlkBy  VARCHAR(255), DBName  VARCHAR(255),
		  Command VARCHAR(255), CPUTime INT,
		  DiskIO INT, LastBatch VARCHAR(255),
		  ProgramName VARCHAR(255), SPID1 INT,
		  REQUESTID INT);
	INSERT INTO #sp_who2 
	EXEC sp_who2
	SELECT      *
	FROM        #sp_who2
	WHERE       DBName <> 'master'  and BlkBy <> '  .' 
	ORDER BY    SPID ASC;
	Set @RC1 = @@ROWCOUNT
	
	DROP TABLE #sp_who2;

Print @RC1
	If @RC1 > 0
	WAITFOR DELAY '00:00:05';   
	Begin
		DROP TABLE IF EXISTS #sp_who3
		CREATE TABLE #sp_who3 (SPID INT, Status VARCHAR(255),
			  Login  VARCHAR(255), HostName  VARCHAR(255),
			  BlkBy  VARCHAR(255), DBName  VARCHAR(255),
			  Command VARCHAR(255), CPUTime INT,
			  DiskIO INT, LastBatch VARCHAR(255),
			  ProgramName VARCHAR(255), SPID1 INT,
			  REQUESTID INT);
		INSERT INTO #sp_who3
		EXEC sp_who2
		SELECT      *
		FROM        #sp_who3
		WHERE       DBName <> 'master'  and BlkBy <> '  .' 
		ORDER BY    SPID ASC;
		Set @RC2 = @@ROWCOUNT
End 

If @RC1 > 0 and @RC2 > 0
Begin
	Declare @S as Varchar(500)
	DECLARE @N as Varchar(100)
	Set @N = (Select Var1 From BPS_Setup Where [SettingName] ='Alerts')
	Set @Run = (Select OnOrOff From [BPS_Setup] Where SettingName = 'Blocking Alert')
	
	Declare @Body as varchar(200)
	Set @Body =  'Blocking Alert '+ @C+ ' '+ @@ServerName + ' '

	Declare @Subject as varchar(200)
	Set @Subject = 'Blocking Alert '
	
	DECLARE @vXML_String AS NVARCHAR (MAX)
	DECLARE @vBody AS NVARCHAR (MAX)
	Set @vBody = ''
	--------------------------------------------------------------------------------------------------------------------------
		
	--------------------------------------------------------------------------------------------------------------------
	--Variable Update: Finalize @vBody Variable Contents
	--------------------------------------------------------------------------------------------------------------------
	SET @vBody =
	'<html>
		<body>
		<style type="text/css">
			table {font-size:8.0pt;font-family:Arial;text-align:left;}
			tr {text-align:left;}
		</style>' +@vBody+ '</body></html>'
	----------------------------------------------------------------------------------------------------------------------
	--Headline
	-----------------------------------------------------------------------------------------------------------------------
	SET @vSubject = 'Blocking Report '+@D+'-'+@C+'-'+@@SERVERNAME
	Set @vBody  = '<B><center>'+@vSubject+'</center></B>'

	------------------------------------------------------------------------------------------------------------------------
	--Blocking Info 
	------------------------------------------------------------------------------------------------------------------------
	SET @vXML_String =
		CONVERT (NVARCHAR (MAX),
			(
				SELECT
						'',X.SPID AS 'td'
					,'',X.Status AS 'td'
					,'',X.Login AS 'td'
					,'',X.HostName AS 'td'
					,'',X.BlkBy AS 'td'
					,'',X.DBName AS 'td'
					,'',X.Command AS 'td'
					,'',X.CPUTime AS 'td'
					,'',X.DiskIO AS 'td'
					,'',X.LastBatch AS 'td'
					,'',X.ProgramName AS 'td'
				FROM
					#sp_who3 X
				WHERE       DBName <> 'master'  and BlkBy <> '  .' 
				ORDER BY
					X.SPID
				FOR
					XML PATH ('tr')
			)
		)

	SET @vBody = @vBody +
	'<br><center>Blocking Alert</center>
	<center>
	<table border=1 cellpadding=10 cellspacing=0>
	<tr>
		<th>SPID</th>
		<th>Status</th>
		<th>Login</th>
		<th>HostName</th>
		<th>BlkBy</th>
		<th>DBName</th>
		<th>Command</th>
		<th>CPUTime</th>
		<th>DiskIO</th>
		<th>LastBatch</th>
		<th>ProgramName</th>
	</tr>'

	SET @vBody = @vBody + @vXML_String
	Set @vBody = @vBody +'</table></center>'

	--Set @vRecipients = 'Mike@BPS-Corp.com'
	----------------------------------------------------------------------------------------------------------------------
	--	sp_send_dbmail: Deliver Results / Notification To End User(s)
	--  Be sure to set profile name
	----------------------------------------------------------------------------------------------------------------------
	EXEC msdb.dbo.sp_send_dbmail
		 @recipients = @vRecipients
		,@profile_name = 'SQL DBMail Profile Name'
		,@subject = @vSubject
		,@body = @vBody
		,@body_format = 'HTML'
	End
End
