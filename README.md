Get started with Predictive Modeling using SQL Server Machine Learning Services

In 2017, Microsoft introduced SQL Server Machine Learning Services letting us run external scripts in SQL Server, and providing easy access to Machine Learning on-premises.

This sample was created to demo SQL Server MLS in the Sydney Business Intelligence Group meet on 19th Feb, 2020 https://www.meetup.com/Sydney-Business-Intelligence-User-Group/events/268056224/

Getting familiar with SQL Server Machine Learning Services - After going over its components and features, a demo was executed to build a Predictive Model using R and SQL Server Machine Learning Services. The prediction in this case is diagnosis of heart disease (angiographic disease status): num

-- Value 0: < 50% diameter narrowing

-- Value 1: > 50% diameter narrowing

#About the Presenter
--------------------

Arjun Sivadasan - http://www.sqlroadie.com


#Demo
--------------------

The demo uses the popular heart disease dataset from UCI. Using R, a predictive model is trained and tested against known results. 

https://archive.ics.uci.edu/ml/machine-learning-databases/heart-disease/processed.cleveland.data

https://archive.ics.uci.edu/ml/machine-learning-databases/heart-disease/heart-disease.names

After testing and comparing a few Machine Learning models, the R scripts were wrapped in SQL Server Stored Procedures letting us execute R scripts through Stored Procedures. The trained models were stored in a SQL Server table, and were used to perform Machine Learning predictions through Stored Procedure calls.

Last step in the demo covered Native Scoring using the native C++ extension capabilities in SQL Server 2017


#Files
--------------------

heart-disease.data - UCI dataset attached for reference 

heart-disease.names - Data description. Go through this file to understand what the variables mean

PredictiveModelingUsingR.r - R script (with comments wherever applicable) that builds the predictive Model using RevoScaleR package. Go through this to understand how the models are created and used for prediction.

PredictiveModelingUsingMLS.sql - SQL script that uses R code covered in the previous file to build a Machine Learning predictive model that is executed in the SQL on premises instance

SQLServer_MachineLearningServices.pptx - Powerpoint presentation used

