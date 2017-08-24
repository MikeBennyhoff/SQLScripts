IF OBJECT_ID('tempdb..#TMP') IS NOT NULL  Begin DROP TABLE #TMP End
CREATE TABLE #TMP (
	X int,
	[server_name] [varchar](100) NULL,
	[edition] [varchar](100) NULL,
	ProductVersion [varchar](100) NULL,
	[level] [varchar](100) NULL,
	[reads] [varchar](100) NULL,
	[writes] [varchar](100) NULL,
	[uptime_days] [varchar](100) NULL,
	[MemInMachine] [varchar](100) NULL,
	[MemPercentFree] int null,
	[Rec_MemForOS] [varchar](100) NULL,
	[Rec_MemForSql] [varchar](100) NULL,
	[MaxServerMemory] [varchar](100) NULL,
	[Max1DatabaseMem] int,
    Cache_Hit_Ratio			[varchar](100) NULL,          
    Memory_Grants_Pending	[varchar](100) NULL,  
    Deadlocks				[varchar](100) NULL,          
    Page_Life_Exp			[varchar](100) NULL,      
    Transactions_Sec		[varchar](100) NULL
) 
Insert Into #TMP(X)
Values (1)

DECLARE @Online_Since AS NVARCHAR (19) DECLARE @Uptime_Days AS INT DECLARE @NetBIOSName as varchar(100) Declare @Edn as Varchar(100) 
Declare @PV as Varchar(100) Declare @Lvl as Varchar(100) Declare @R as Varchar(100) Declare @W as Varchar(100)

Set	@R = REVERSE (SUBSTRING (REVERSE (CONVERT (VARCHAR (15), CONVERT (MONEY, @@TOTAL_READ), 1)), 4, 15)) 
Set @W = REVERSE (SUBSTRING (REVERSE (CONVERT (VARCHAR (15), CONVERT (MONEY, @@TOTAL_WRITE), 1)), 4, 15)) 
Set @Lvl = Cast(SERVERPROPERTY ('ProductLevel') as Varchar(250)) 
Set @PV = Cast(SERVERPROPERTY ('ProductVersion') as varchar(250)) 
Set @Edn = REPLACE (CONVERT (NVARCHAR (128), SERVERPROPERTY ('Edition')),' Edition','') 
Set @Uptime_Days = (SELECT datediff(dd,create_date,getdate()) FROM sys.databases WHERE name = 'tempdb')

---------------------------------------------------------------------------------------------------------------------
DECLARE @memInMachine DECIMAL(9,2) DECLARE @memOsBase DECIMAL(9,2) DECLARE @memOs4_16GB DECIMAL(9,2) DECLARE @memOsOver_16GB DECIMAL(9,2)
DECLARE @memOsTot DECIMAL(9,2) DECLARE @memForSql DECIMAL(9,2) DECLARE @CurrentMem DECIMAL(9,2) DECLARE @sql VARCHAR(1000)

IF OBJECT_ID('tempdb..#mem ') IS NOT NULL  Begin DROP TABLE #mem End 
CREATE TABLE #mem(mem DECIMAL(9,2))
--Get current mem setting----------------------------------------------------------------------------------------------
SET @CurrentMem = (SELECT CAST(value AS INT)/1024. FROM sys.configurations WHERE name = 'max server memory (MB)')

--Get memory in machine------------------------------------------------------------------------------------------------
IF CAST(LEFT(CAST(SERVERPROPERTY('ResourceVersion') AS VARCHAR(20)), 1) AS INT) = 9
  SET @sql = 'SELECT physical_memory_in_bytes/(1024*1024*1024.) FROM sys.dm_os_sys_info'
ELSE 
   IF CAST(LEFT(CAST(SERVERPROPERTY('ResourceVersion') AS VARCHAR(20)), 2) AS INT) >= 11
     SET @sql = 'SELECT physical_memory_kb/(1024*1024.) FROM sys.dm_os_sys_info'
   ELSE
     SET @sql = 'SELECT physical_memory_in_bytes/(1024*1024*1024.) FROM sys.dm_os_sys_info'

SET @sql = 'DECLARE @mem decimal(9,2) SET @mem = (' + @sql + ') INSERT INTO #mem(mem) VALUES(@mem)'
--PRINT @sql
EXEC(@sql)
SET @memInMachine = (SELECT MAX(mem) FROM #mem)

Declare @MemUtil as int
Set @MemUtil =(Select memory_utilization_percentage From sys.dm_os_process_memory)

--Calculate recommended memory setting---------------------------------------------------------------------------------
SET @memOsBase = 1
SET @memOs4_16GB = 
  CASE 
    WHEN @memInMachine <= 4 THEN 0
   WHEN @memInMachine > 4 AND @memInMachine <= 16 THEN (@memInMachine - 4) / 4
    WHEN @memInMachine >= 16 THEN 3
  END

SET @memOsOver_16GB = 
  CASE 
    WHEN @memInMachine <= 16 THEN 0
   ELSE (@memInMachine - 16) / 8
  END

SET @memOsTot = @memOsBase + @memOs4_16GB + @memOsOver_16GB
SET @memForSql = @memInMachine - @memOsTot
---------------------------------------------------------------------------
Declare @XL as int
Set @XL =(SELECT convert(nvarchar(128), value_in_use) 
FROM sys.configurations WHERE [name] = N'xp_cmdshell')

Update #TMP
	Set --Online_Since			= @Online_Since,
		uptime_days				= @Uptime_Days,
		--Netbios_nam			= @NetBIOSName,
		Server_Name				= @@SERVERNAME,
		Reads					= @R,
		Writes					= @W,
		[Level]					= @Lvl,
		ProductVersion			= @PV,
		Edition					= @Edn,
		[MaxServerMemory]		= @CurrentMem,
		MemInMachine			= @memInMachine,
		[MemPercentFree]		= @MemUtil,
		Rec_MemForOS			= @memOsTot,
		Rec_MemForSql			= @memForSql
		
IF object_id('tempdb..#OSPC') IS NOT NULL BEGIN
    DROP TABLE #OSPC
END

DECLARE @FirstCollectionTime DateTime
    , @SecondCollectionTime DateTime
    , @NumberOfSeconds Int
    , @BatchRequests Float
    , @LazyWrites Float
    , @Deadlocks BigInt
    , @PageLookups Float
    , @PageReads Float
    , @PageWrites Float
    , @SQLCompilations Float
    , @SQLRecompilations Float
    , @Transactions Float

DECLARE @CounterPrefix NVARCHAR(30)
SET @CounterPrefix = CASE WHEN @@SERVICENAME = 'MSSQLSERVER'
THEN 'SQLServer:'
ELSE 'MSSQL$' + @@SERVICENAME + ':'
END

SELECT counter_name, cntr_value--, cntr_type --I considered dynamically doing each counter type, but decided manual was better in this case
INTO #OSPC 
FROM sys.dm_os_performance_counters 
WHERE object_name like @CounterPrefix + '%'
    AND instance_name IN ('', '_Total')
    AND counter_name IN ( N'Batch Requests/sec'
                        , N'Buffer cache hit ratio'
                        , N'Buffer cache hit ratio base'
                        , N'Free Pages'
                        , N'Lazy Writes/sec'
                        , N'Memory Grants Pending'
                        , N'Number of Deadlocks/sec'
                        , N'Page life expectancy'
                        , N'Page Lookups/Sec'
                        , N'Page Reads/Sec'
                        , N'Page Writes/Sec'
                        , N'SQL Compilations/sec'
                        , N'SQL Re-Compilations/sec'
                        , N'Target Server Memory (KB)'
                        , N'Total Server Memory (KB)'
                        , N'Transactions/sec')

Update #TMP
Set #TMP.Cache_Hit_Ratio	= cntr_value
From #TMP Inner Join #OSPC on 1 = 1 
Where counter_name = 'Buffer cache hit ratio'

Update #TMP
Set #TMP.Memory_Grants_Pending = cntr_value
From #TMP Inner Join #OSPC on 1 = 1 
Where counter_name = 'Memory Grants Pending'

Update #TMP
Set #TMP.Deadlocks	= cntr_value
From #TMP Inner Join #OSPC on 1 = 1 
Where counter_name = 'Number of Deadlocks/sec'

Update #TMP
Set #TMP.Page_Life_Exp	= cntr_value
From #TMP Inner Join #OSPC on 1 = 1 
Where counter_name = 'Page life expectancy'

Update #TMP
Set #TMP.Transactions_Sec	= cntr_value
From #TMP Inner Join #OSPC on 1 = 1 
Where counter_name = 'Transactions/sec'

Declare @CG as float
Set @CG = (SELECT (a.cntr_value * 1.0 / b.cntr_value) * 100.0 as BufferCacheHitRatio
FROM sys.dm_os_performance_counters  a
JOIN  (SELECT cntr_value, OBJECT_NAME 
    FROM sys.dm_os_performance_counters  
    WHERE counter_name = 'Buffer cache hit ratio base'
        AND OBJECT_NAME = 'SQLServer:Buffer Manager') b ON  a.OBJECT_NAME = b.OBJECT_NAME
WHERE a.counter_name = 'Buffer cache hit ratio'
AND a.OBJECT_NAME = 'SQLServer:Buffer Manager')

Update #TMP Set  Cache_Hit_Ratio	= @CG

--First PASS
DECLARE @First INT
DECLARE @Second INT
SELECT @First = cntr_value
FROM sys.dm_os_performance_counters
WHERE OBJECT_NAME LIKE '%Databases%' 
AND counter_name like '%Transactions/sec%'
AND instance_name like '%_Total%';

--SELECT @First
--Following is the delay
WAITFOR DELAY '00:00:05'

SELECT @Second = cntr_value
FROM sys.dm_os_performance_counters
WHERE OBJECT_NAME LIKE '%Databases%' 
AND counter_name like '%Transactions/sec%'
AND instance_name like '%_Total%';
--SELECT @Second

Declare @TS as float
Set @TS = (SELECT (@Second - @First)) 

Update #TMP
	Set Transactions_Sec = @TS

Select * From #TMP


		










