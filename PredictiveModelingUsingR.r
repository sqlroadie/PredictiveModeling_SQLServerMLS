#--------------------------------------------
#1. Import heart disease data from SQL Server
#--------------------------------------------
connStr <- paste("Driver=SQL Server; Server=PREDATOR\\ARJUN", ";Database=", "Tutorialdb", ";Trusted_Connection=true;", sep = "");

SQL_heartdata <- RxSqlServerData(table = "dbo.HeartDiseaseObservation",connectionString = connStr, returnDataFrame = TRUE);

heartdata <- rxImport(SQL_heartdata);

head(heartdata)

str(heartdata)

#--------------------------------------------
#2. Data Preparation
#--------------------------------------------
#Replace ? with NA, which is a missing value indicator
heartdata[heartdata == "?"] <- NA

#Exclude observations with missing values 
heartdata <- heartdata[complete.cases(heartdata),]

#num > 0 are cases of heart disease
heartdata$num[heartdata$num > 0] <- 1
barplot(table(heartdata$num), main="Fate", col="black")

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

levels(heartdata$num) = c("no disease","disease")
levels(heartdata$sex) = c("female","male","")
# mosaicplot(heartdata$sex ~ heartdata$num,
           # main="Fate by Gender", shade=FALSE,color=TRUE,
           # xlab="Gender", ylab="Heart disease")

str(heartdata)

#-------------------------------------------------------
#3. Splitting data into training (70%) and testing (30%)
#-------------------------------------------------------

library(caret)

training <- createDataPartition(heartdata$num,p=0.7,list=FALSE)
traindata <- heartdata[training,]
testdata <- heartdata[-training,]

#Check ratio
nrow(traindata) / (nrow(traindata) + nrow(testdata))

#Build models using training data
fo_heartdata <- as.formula(paste("num ~ ",paste(colnames(heartdata)[1:13], collapse = "+")))

fo_heartdata

#--------------------------------------------
#4.Build model using training data
#--------------------------------------------
#Decision Tree model
dtree_heartdata <- rxDTree(fo_heartdata, data = traindata) #reportProgress=0

#Decision Forest
dforest_heartdata <- rxDForest(fo_heartdata, data = traindata) 

#Boosted Trees
btrees_heartdata <- rxBTrees(fo_heartdata, data = traindata, lossFunction = "multinomial")

#--------------------------------------------------------------------------------------
#5.Predict using the generated models and compare Accuracy, Sensitivity and Specificity
#--------------------------------------------------------------------------------------
#Prediction
pred_dtree_heart <- rxPredict(dtree_heartdata, testdata, type="class", writeModelVars = TRUE) 
head(pred_dtree_heart,3)
confusionMatrix(pred_dtree_heart$num_Pred,pred_dtree_heart$num)

pred_dforest_heart <- rxPredict(dforest_heartdata, testdata, writeModelVars = TRUE)
head(pred_dforest_heart,3)
confusionMatrix(pred_dforest_heart$num_Pred,pred_dforest_heart$num) #0.87

pred_btrees <- rxPredict(btrees_heartdata, testdata, writeModelVars = TRUE)
head(pred_btrees,3)
confusionMatrix(pred_btrees$num_Pred,pred_btrees$num) #0.90


