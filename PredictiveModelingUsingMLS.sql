--Heart disease data from UCI imported to table HeartDiseaseObservation
--https://archive.ics.uci.edu/ml/machine-learning-databases/heart-disease/processed.cleveland.data

-- USE [TutorialDB]
-- GO
--Table schema for references
-- CREATE TABLE [dbo].[HeartDiseaseObservation](
	-- [age] [float] NOT NULL,
	-- [sex] [float] NOT NULL,
	-- [cp] [float] NOT NULL,
	-- [trestbps] [float] NOT NULL,
	-- [chol] [float] NOT NULL,
	-- [fbs] [float] NOT NULL,
	-- [restecg] [float] NOT NULL,
	-- [thalach] [float] NOT NULL,
	-- [exang] [float] NOT NULL,
	-- [oldpeak] [float] NOT NULL,
	-- [slope] [float] NOT NULL,
	-- [ca] [nvarchar](50) NOT NULL,
	-- [thal] [nvarchar](50) NOT NULL,
	-- [num] [int] NOT NULL
-- ) ON [PRIMARY]
-- GO

--Create table to store models
sp_configure 'external scripts enabled', 1;

reconfigure
go

USE [TutorialDB]
GO

--Step 1: Create table to store model
CREATE TABLE [dbo].[heartdisease_rx_models](
	[model_name] [varchar](30) NOT NULL DEFAULT ('default model'),
	[model] [varbinary](max) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[model_name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

--ALTER the observations table to split data for training and testing
ALTER TABLE dbo.HeartDiseaseObservation 
ADD datausage CHAR(5) ;
GO

--Remove invalid observations
select * from dbo.HeartDiseaseObservation where ca = '?' or thal = '?'
delete from dbo.HeartDiseaseObservation where ca = '?' or thal = '?'

--Observations where num > 0 are cases of heart disease. Assign 1 to have just two values for num - 0 and 1
update dbo.HeartDiseaseObservation 
set num = 1
where num > 0

----Reset datausage
--update dbo.HeartDiseaseObservation
--set datausage = NULL

--Split data for training (70%) and testing (30%)
;with cteHD
as
(
	select top(70) percent *
	from dbo.HeartDiseaseObservation
	order by newid()
)

update cteHD
set datausage = 'train'

update dbo.HeartDiseaseObservation
set datausage = 'test'
where datausage is null


USE TutorialDB;

--STEP 2 - Train model using RevoscaleR
--Stored procedure that trains and generates an R model using heart disease data and Boosted Trees algorithm
DROP PROCEDURE IF EXISTS generate_heartdisease_rx_model;
go
CREATE PROCEDURE generate_heartdisease_rx_model (@trained_model varbinary(max) OUTPUT)
AS
BEGIN
    EXECUTE sp_execute_external_script
				@language = N'R', 
				@script = N'
						require("RevoScaleR");

						##Convert multiple columns of a dataframe to specified data types
						convert.magic <- function(obj,types){
							 for (i in 1:length(obj)){
								 FUN <- switch(types[i],character = as.character, 
															numeric = as.numeric, 
															factor = as.factor)
								 obj[,i] <- FUN(obj[,i])
							 }
							 obj
						 }
 
						chclass <-c("numeric","factor","factor","numeric","numeric","factor","factor","numeric","factor","numeric","factor","factor","factor","factor")

						traindata <- convert.magic(traindata,chclass)

						#Build models using training data
						fo_heartdata <- as.formula(paste("num ~ ",paste(colnames(traindata)[1:13], collapse = "+")))

						#Boosted Trees
						btrees_heartdata <- rxBTrees(fo_heartdata, data = traindata, lossFunction = "multinomial")						
						
						#Before saving the model to the DB table, we need to serialize it
						trained_model <- as.raw(serialize(btrees_heartdata, connection=NULL));'

    , @input_data_1 = N'select "age", "sex", "cp", "trestbps", "chol", "fbs", "restecg", "thalach", "exang", "oldpeak", "slope", "ca", "thal", "num" from dbo.HeartDiseaseObservation where datausage =''train'''
    , @input_data_1_name = N'traindata'
    , @params = N'@trained_model varbinary(max) OUTPUT'
    , @trained_model = @trained_model OUTPUT;
END;
GO

--STEP 3 - Save model to table
TRUNCATE TABLE dbo.heartdisease_rx_models;

--Execute Stored Procedure to generate trained model using dtree algorithm
DECLARE @model VARBINARY(MAX);
EXEC dbo.generate_heartdisease_rx_model @model OUTPUT;

INSERT INTO dbo.heartdisease_rx_models (model_name, model) VALUES('rxBTrees', @model);

SELECT * FROM dbo.heartdisease_rx_models;

USE TutorialDB
go

-- STEP 4 - Use the RevoScaleR rxPredict function to predict number of heart disease cases 
--Stored procedure that accepts model name and new data as input parameters and predicts heart disease risk for the new data
DROP PROCEDURE IF EXISTS predict_heartdisease;
GO
CREATE PROCEDURE predict_heartdisease (@model VARCHAR(100),@q NVARCHAR(MAX))
AS
BEGIN
	--Fetch the trained model data from table heartdisease_rx_models
    DECLARE @rx_model VARBINARY(MAX) = (SELECT model FROM dbo.heartdisease_rx_models WHERE model_name = @model);
    
	EXECUTE sp_execute_external_script
				@language = N'R',
				@script = N'require("RevoScaleR");

						#The InputDataSet contains the new data passed to this stored proc. We will use this data to predict.
						heartdata = heartdiseasedataset;

						##Convert multiple columns of a dataframe to specified data types
						convert.magic <- function(obj,types){
							 for (i in 1:length(obj)){
								 FUN <- switch(types[i],character = as.character, 
															numeric = as.numeric, 
															factor = as.factor)
								 obj[,i] <- FUN(obj[,i])
							 }
							 obj
						 }
 
						chclass <-c("numeric","factor","factor","numeric","numeric","factor","factor","numeric","factor","numeric","factor","factor","factor","factor")

						heartdata <- convert.magic(heartdata,chclass)

						#Before using the model to predict, we need to unserialize it
						heartdisease_model = unserialize(rx_model);

						#Call prediction function				
						heartdisease_prediction <- rxPredict(heartdisease_model, heartdata, extraVarsToWrite="num")',
						
				@input_data_1 = @q,
				@input_data_1_name = N'heartdiseasedataset', 
				@output_data_1_name = N'heartdisease_prediction',
                @params = N'@rx_model varbinary(max)', --Trained model passed as parameter to external R script
                @rx_model = @rx_model
                WITH RESULT SETS (("X0_Prob" float, "X1_Prob" float,"num_Pred" int, "num" int));

END;
GO


--Execute the predict_heartdisease stored proc and pass the modelname and a query string with a set of features we want to use to predict heart disease risk
EXEC dbo.predict_heartdisease @model = 'rxBTrees',
       @q ='select "age", "sex", "cp", "trestbps", "chol", "fbs", "restecg", "thalach", "exang", "oldpeak", "slope", "ca", "thal", "num" from dbo.HeartDiseaseObservation where datausage =''test''';
GO

/*Native Scoring - introduced in SQL Server MLS 2017*/

USE TutorialDB;

--STEP 1 - Setup model table for storing native/serialized model

CREATE TABLE [dbo].[heartdisease_models](
	[model_name] [varchar](30) NOT NULL DEFAULT('default model'),
	[lang] [varchar](30) NOT NULL,
	[model] [varbinary](max) NULL,
	[native_model] [varbinary](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[model_name] ASC,
	[lang] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO


--STEP 2 - Train model using RevoscaleR
DROP PROCEDURE IF EXISTS generate_heartdisease_R_native_model;
go
--Accept model type as input and conditionally generate Linear Regression or Decision Tree model
CREATE PROCEDURE generate_heartdisease_R_native_model (@model_type varchar(30), @trained_model varbinary(max) OUTPUT)
AS
BEGIN
    EXECUTE sp_execute_external_script
      @language = N'R'
    , @script = N'
				require("RevoScaleR")

				##Convert multiple columns of a dataframe to specified data types
				convert.magic <- function(obj,types){
					 for (i in 1:length(obj)){
						 FUN <- switch(types[i],character = as.character, 
													numeric = as.numeric, 
													factor = as.factor)
						 obj[,i] <- FUN(obj[,i])
					 }
					 obj
				 }

				chclass <-c("numeric","factor","factor","numeric","numeric","factor","factor","numeric","factor","numeric","factor","factor","factor","factor")

				traindata <- convert.magic(traindata,chclass)

				#Build models using training data
				fo_heartdata <- as.formula(paste("num ~ ",paste(colnames(traindata)[1:13], collapse = "+")))

				if(model_type == "decisionforest") {
					#Create a Decision Forest model and train it using the training data set
					model_dforest <- rxDForest(fo_heartdata, data = traindata);
					#Note use of the parameter realtimeScoringOnly. When set to true, the rxSerializeModel function drops fields that are not essential for real-time scoring.
					trained_model <- rxSerializeModel(model_dforest, realtimeScoringOnly = TRUE);
					}
				
				if(model_type == "boostedtrees") {
					#Create a Boosted Trees model and train it using the training data set
					model_btrees <- rxBTrees(fo_heartdata, data = traindata, lossFunction = "multinomial");
					#Note use of the parameter realtimeScoringOnly. When set to true, the rxSerializeModel function drops fields that are not essential for real-time scoring.
					trained_model <- rxSerializeModel(model_btrees, realtimeScoringOnly = TRUE);
					}'

    , @input_data_1 = N'select "age", "sex", "cp", "trestbps", "chol", "fbs", "restecg", "thalach", "exang", "oldpeak", "slope", "ca", "thal", "num" from dbo.HeartDiseaseObservation where datausage =''train'''
    , @input_data_1_name = N'traindata'
    , @params = N'@trained_model varbinary(max) OUTPUT, @model_type varchar(30)'
	, @model_type = @model_type
    , @trained_model = @trained_model OUTPUT;
END;
GO

--STEP 3 - Save model to table

--Line of code to empty table
--TRUNCATE TABLE dbo.heartdisease_models;

--Save Linear model to table
DECLARE @model VARBINARY(MAX);
EXEC dbo.generate_heartdisease_R_native_model "decisionforest", @model OUTPUT;
INSERT INTO dbo.heartdisease_models (model_name, native_model, lang) VALUES('decisionforest_model', @model, 'R');

--Save DTree model to table
DECLARE @model2 VARBINARY(MAX);
EXEC dbo.generate_heartdisease_R_native_model "boostedtrees", @model2 OUTPUT;
INSERT INTO dbo.heartdisease_models (model_name, native_model, lang) VALUES('boostedtrees_model', @model2, 'R');

-- Look at the models in the table
SELECT * FROM dbo.heartdisease_models;

GO

-- STEP 4  - Use the native PREDICT (native scoring) to predict number of heart disease cases for both models
--Now lets predict using native scoring with linear model
DECLARE @model VARBINARY(MAX) = (SELECT TOP(1) native_model FROM dbo.heartdisease_models WHERE model_name = 'decisionforest_model' AND lang = 'R');

;with cteHeartDisease as (select * from dbo.HeartDiseaseObservation where [DataUsage] = 'test')
--Pass either table, CTE, view or Table Valued function as DATA
SELECT d.*, p.* FROM PREDICT(MODEL = @model, DATA = cteHeartDisease AS d) WITH([0_prob] float, [1_prob] float, [num_Pred] int) AS p;
GO

--Native scoring with dtree model
DECLARE @model VARBINARY(MAX) = (SELECT TOP(1) native_model FROM dbo.heartdisease_models WHERE model_name = 'boostedtrees_model' AND lang = 'R');
SELECT d.*, p.* FROM PREDICT(MODEL = @model, DATA = dbo.HeartDiseaseObservation AS d) WITH([0_prob] float, [1_prob] float, [num_Pred] int) AS p;
GO



