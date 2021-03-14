USE master;
---------------------------------------------------------------------------------------
-- Create DateBase
CREATE DATABASE ExaminationSystem;

-- Alter db to add new filegroup
ALTER DATABASE ExaminationSystem
ADD FILEGROUP FGDefault
GO

-- Alter db to add secondary file
ALTER DATABASE ExaminationSystem
ADD FILE
( 
	NAME = 'DFNew',
	FILENAME ='C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\ExaminationSystemSecond.ndf',
	SIZE = 2MB,
	MAXSIZE=5000,
	FILEGROWTH=1
)
TO FILEGROUP FGDefault;	

-- set the file group => the default file group
ALTER DATABASE ExaminationSystem 
  MODIFY FILEGROUP 
  FGDefault DEFAULT;
GO

---------------------------------------------------------------------------------------

USE ExaminationSystem;
GO

---- >> CREATE TABLES << ----

-- 1. Question type table
CREATE TABLE QuestionType(
ID INT IDENTITY PRIMARY KEY,
Type NVARCHAR(100)
)

-- 2. Question table
CREATE TABLE Question(
ID INT IDENTITY PRIMARY KEY,
Question NVARCHAR(max) NOT NULL,
answer INT NOT NULL, -- store 0 or 1 for true or false OR answer id
typeID int NOT NULL REFERENCES QuestionType(ID)
);

-- ALTER TABLE Question
-- ADD CONSTRAINT QuestionAnswerFK FOREIGN KEY (answerID) REFERENCES Choices(ID);

-- 3. Choices
CREATE TABLE Choices(
ID INT IDENTITY PRIMARY KEY,
answer NVARCHAR(max),
QuestionID int NOT NULL REFERENCES Question(ID)
); 

-- 4. Course
CREATE TABLE Course(
ID INT IDENTITY PRIMARY KEY,
Name NVARCHAR(max),
Description NVARCHAR(max),
MaxDegree int,
MinDegree int
); 

-- 5. Question Pool => questions for each course
CREATE TABLE QuestionPool(
ID INT IDENTITY PRIMARY KEY,
QuestionID int NOT NULL,
CourseID int NOT NULL,
CONSTRAINT UC_Course_Question UNIQUE (QuestionID,CourseID)
);

ALTER TABLE  QuestionPool
--ADD CONSTRAINT FK_Question_Course FOREIGN KEY (CourseID) REFERENCES Course(ID) ON DELETE CASCADE
ADD CONSTRAINT FK_QuestP_Quest FOREIGN KEY (QuestionID) REFERENCES Question(ID) ON DELETE CASCADE

-- 6. Instructor
CREATE TABLE Instructor(
ID INT IDENTITY PRIMARY KEY,
FirstName NVARCHAR(max),
LastName NVARCHAR(max)
);

-- 7. Class
CREATE TABLE Class(
ID INT IDENTITY PRIMARY KEY,
Code NVARCHAR(100),
Year int default Year(getdate())
);

-- 8. Class Course 
CREATE TABLE ClassCourse (
ID INT IDENTITY PRIMARY KEY,
InstructorID int NOT NULL REFERENCES Instructor(ID),
CourseID int NOT NULL REFERENCES Course(ID),
ClassID int NOT NULL REFERENCES Class(ID),
CONSTRAINT UC_Course_Instructor UNIQUE (InstructorID,CourseID,ClassID)
);

-- 9. Student
CREATE TABLE Student(
ID INT IDENTITY PRIMARY KEY,
FirstName NVARCHAR(max),
LastName NVARCHAR(max),
ClassID int REFERENCES Class(ID),
);

-- 10. Exam
CREATE TABLE Exam(
ID INT IDENTITY PRIMARY KEY,
CourseID int NOT NULL REFERENCES Course(ID),
Year DATETIME DEFAULT GETDATE(),
StartTime DATETIME NOT NULL,
EndTime DATETIME NULL,
TotalTime VARCHAR(5) NOT  NULL,
Degree decimal,
State VARCHAR(10) CHECK(State IN('exam', 'corrective')),
InstructorID int REFERENCES Instructor(ID)
);

--ALTER TABLE Exam ALTER COLUMN TotalTime VARCHAR(5) NOT  NULL

-- 11. Exam Questions
CREATE TABLE ExamQuestions(
ID INT IDENTITY PRIMARY KEY,
ExamID int NOT NULL REFERENCES Exam(ID),
QuestionID int NOT NULL REFERENCES Question(ID),
Degree decimal,
);
-- 12. Student Exam
CREATE TABLE StudentExams(
ID INT IDENTITY PRIMARY KEY,
ExamID int NOT NULL REFERENCES Exam(ID),
StudentID int NOT NULL REFERENCES Student(ID),
Result INT,
);

-- 13. Student answers
CREATE TABLE StudentAnswers(
ID INT IDENTITY PRIMARY KEY,
StudentID int NOT NULL REFERENCES Student(ID),
ExamID int NOT NULL REFERENCES Exam(ID),
QuestionID int NOT NULL REFERENCES Question(ID),
Answer int,
Correct int 
);

GO

---------------------------------------------------------------------------------------
---- >> Views << ----

GO
 
-- 1. get instructor courses
CREATE VIEW InstructorCources
AS
(
  SELECT I.ID [Instructor ID], I.FirstName+' '+I.LastName [Instructor name],
  C.Name [Course name],ISNULL(C.Description, '____') [Couese Description],
  C.MaxDegree, C.MinDegree, CL.Code [Class]
  FROM 
  Instructor I JOIN ClassCourse CC ON  I.ID = CC.InstructorID
  JOIN Course C ON CC.CourseID = C.ID JOIN Class CL ON CL.ID = CC.ClassID
);

GO

-- 2. get questions for course (question pool)
CREATE VIEW CourseQuestions
AS
(
   SELECT Q.ID, 'True & False' Type, C.Name [Course name], Q.Question,
   CASE Q.answer WHEN 1 THEN 'True' When 0 then 'False' END [Answer]
   FROM Course C JOIN QuestionPool QP ON QP.CourseID = C.ID
   JOIN Question Q ON Q.ID = QP.QuestionID 
   WHERE Q.typeID=1
   UNION
   SELECT Q.ID, 'Multi-Choice' Type, C.Name [Course name], Q.Question, CS.answer
   FROM Course C JOIN QuestionPool QP ON QP.CourseID = C.ID
   JOIN Question Q ON Q.ID = QP.QuestionID 
   JOIN Choices CS ON CS.ID = Q.answer 
   WHERE Q.typeID=2
);

GO

-- 3. get course exam question
CREATE VIEW CourseExam
AS
(
   SELECT E.ID, C.Name ,I.FirstName+' '+I.LastName [Created by], 
          E.StartTime, E.EndTime, E.TotalTime,E.Degree, YEAR(E.Year) [year]
   FROM Exam E, Course C, Instructor I
   WHERE E.CourseID=C.ID AND I.ID=E.InstructorID
);

GO
---------------------------------------------------------------------------------------
---- >> TYPES << ----
-- this table type used to pass multi-choices to DB
CREATE TYPE AnswerList
AS TABLE
(
  Answer NVARCHAR(MAX), -- the choice
  TRUE INT -- 1 if true 0 if not
);
GO

CREATE TYPE QuestionList
AS TABLE
(
  quesID int, 
  degree decimal 
);
GO

CREATE TYPE StudentAnswerList
AS TABLE
(
  quesID int, 
  answer int 
);
GO
---------------------------------------------------------------------------------------
---- >> Functions << ----

-- check if an instructor teaches the given course or not
CREATE FUNCTION IsCourseInstrctor(@instrID int, @CourseID int)
RETURNS INT
AS
BEGIN
  DECLARE @True int
  SELECT DISTINCT @True=InstructorID
  FROM ClassCourse WHERE InstructorID = @instrID and CourseID= @CourseID  
  SET @True = @@ROWCOUNT
  RETURN @True
END
GO

-- get questions of specific course
CREATE FUNCTION GetCourseQuestions(@course NVARCHAR(max))
RETURNS TABLE AS 
RETURN
(
  SELECT * FROM CourseQuestions where [Course name]=@course
)
GO

-- add time ('hh:mm') for datetime
CREATE FUNCTION AddTime(@date datetime, @time VARCHAR(5))
RETURNS DATETIME
AS
BEGIN
	 DECLARE @date2 DATETIME, @dt datetime

	 select @dt = cast(@time as datetime)
	 SELECT @date2 = DATEADD(HOUR,DATEPART(HOUR,@dt) ,@date)
	 SELECT @date2 = DATEADD(MINUTE,DATEPART(MINUTE,@dt),@date2)
	 RETURN @date2 
END
GO

-- get questions of specific exam
CREATE FUNCTION GetExamQuestions(@examID int)
RETURNS TABLE AS 
RETURN
(
  SELECT Q.ID [Question ID], Q.Question, 'True & False' Type, EQ.Degree,
  CASE answer WHEN '0' THEN 'false' ELSE 'true' END AS 'answer',
  q.answer [answer id]
  FROM ExamQuestions EQ JOIN Question Q ON Q.ID=EQ.QuestionID
  WHERE EQ.ExamID = @examID AND Q.typeID=1
  UNION
  SELECT Q.ID [Question ID], Q.Question, 'Multi-Choice' Type, 
  EQ.Degree, C.answer [answer], q.answer [answer id]
  FROM ExamQuestions EQ JOIN Question Q ON Q.ID=EQ.QuestionID
  JOIN Choices C ON C.ID = Q.answer
  WHERE EQ.ExamID = @examID AND Q.typeID=2
)
GO

-- get question choices
CREATE FUNCTION GetQuestionsChoices(@quesID int)
RETURNS TABLE AS 
RETURN
(
  SELECT * FROM Choices WHERE QuestionID=@quesID
)
GO


---------------------------------------------------------------------------------------
---- >> Procedures << ---- 
GO
/* Assume that we have an application that provides login for the instructor
   so we can pass (@instrID) to the database when he takes some actions:  */

--- 1. Add true or false question in course question pool 
---    ==> used by teacher (when he chooses a specific course)
GO
CREATE PROC AddTrueFalseQues(
     @instrID INT,   
	 @CourseID INT, 
     @Question NVARCHAR(MAX),
     @answer VARCHAR(4)
   )
AS 
BEGIN

  DECLARE @true int, @isInstructor int;
  -- first check if this instructor teach this course 
  SET @isInstructor =  dbo.IsCourseInstrctor(@instrID, @CourseID);

  IF @isInstructor = 1  -- if yes insert his input
  BEGIN
     IF @answer IN ('TRUE', 'T')
        SET @true = 1
     ELSE 
        SET @true = 0

	 -- question type id for true or false = 1
     INSERT INTO Question (Question, typeID, answer) VALUES (@Question, 1, @true) 

     -- add this question to question poll for this course
     INSERT INTO QuestionPool (QuestionID, CourseID) values (SCOPE_IDENTITY(), @CourseID)
   END
  ELSE          -- if not => don't insert
     SELECT 'This instructor doesnt teach this course'
END
GO

--- 2. Add muli-choice question in course question pool 
-->    used by teacher (when he chooses a specific course)
-->    Choices passed to procedure as table of type AnswerList
CREATE PROC AddMultiChoiceQues(
     @instrID int,   
	 @CourseID INT, 
     @Question NVARCHAR(MAX),
     @answerList AS DBO.AnswerList READONLY
   )
AS 
BEGIN
  SET NOCOUNT ON;

  DECLARE @CorrectId int, @isInstructor int, @QuestionID INT

  -- first check if this instructor teach this course 
  SET @isInstructor =  dbo.IsCourseInstrctor(@instrID, @CourseID);

  IF @isInstructor=1  -- if yes insert his input
  BEGIN

	 -- question type id for multi-choice = 2
     INSERT INTO Question (Question, typeID, answer) VALUES (@Question, 2, 0) 

	 SET @QuestionID = SCOPE_IDENTITY(); -- get the id of the insereted ques.

     -- add this question to question poll for this course
     INSERT INTO QuestionPool (QuestionID, CourseID) values (@QuestionID, @CourseID)

	 -- insert the given choices to choices table
	 INSERT INTO Choices (answer, QuestionID) 
	 SELECT Answer, @QuestionID  FROM @answerList
	 
	 -- find the correct answer id and update question tuple to add it
	 SELECT @CorrectId = C.ID
	 FROM @answerList L JOIN Choices C ON C.answer=L.Answer
	 WHERE L.true=1

	 UPDATE QUESTION SET answer=@CorrectId WHERE ID=@QuestionID
	 
   END
   ELSE          -- if not => don't insert
     SELECT 'This instructor doesnt teach this course'
END
GO

--- 3. Delete question in course question pool 
CREATE PROC DeleteQuestion (
     @instrID int,   
     @QuestionID int
)
AS
BEGIN
   DECLARE @isInstructor int, @type int, @CourseID int;

   -- get course id
   SELECT @CourseID = CourseID FROM QuestionPool WHERE QuestionID=@QuestionID

   -- check if this instructor teach this course 
   SET @isInstructor =  dbo.IsCourseInstrctor(@instrID, @CourseID);

   IF @isInstructor=1  -- if yes delete the question
   BEGIN
     SELECT @type=typeID FROM Question WHERE ID=@QuestionID
	 IF @type=2
	    DELETE FROM Choices WHERE QuestionID = @QuestionID

     DELETE FROM Question WHERE ID=@QuestionID
   END
   ELSE          -- if not => don't delete
     SELECT 'This instructor doesnt teach this course'
END 

GO

--- 4. update question in course question pool (true of false type)
CREATE PROC UpdateTrueFalseQues (
     @instrID int,   
     @QuestionID int,  
     @Question NVARCHAR(MAX) = NULL,
     @answer VARCHAR(4) = NULL
   )
AS 
BEGIN
  BEGIN TRY
	DECLARE @true int, @isInstructor int, @CourseID int, @type int;

	-- get question type
	SELECT @type=typeID FROM Question WHERE ID=@QuestionID

	-- throw an error if question type not 'true or false'
	IF @type!=1
		THROW 51000, 'This question doesnt belong to "true or false" question type', 1;  
    
    -- get course id
    SELECT @CourseID = CourseID FROM QuestionPool WHERE QuestionID=@QuestionID

	--  check if this instructor teach this course 
	SET @isInstructor =  dbo.IsCourseInstrctor(@instrID, @CourseID);

    IF (@isInstructor=1)  -- if yes update the question
	BEGIN
	   IF (@answer IS NOT NULL)
	   BEGIN
		 IF @answer IN ('TRUE', 'T')
			SET @true = 1
		 ELSE 
			SET @true = 0
		 UPDATE Question SET answer=@true WHERE ID=@QuestionID
       END
	   
	   IF (@Question IS NOT NULL)
	   UPDATE Question SET Question=@Question WHERE ID=@QuestionID

	END
	ELSE          -- if not => don't update 
		SELECT 'This instructor doesnt teach this course'
  END TRY
  BEGIN CATCH
     SELECT ERROR_MESSAGE();
  END CATCH
END 
GO 

--- 5. update question in course question pool (multi-choice type)
CREATE PROC UpdateMultiChoiceQues(
     @instrID int,   
	 @QuestionID int,  
     @Question NVARCHAR(MAX) = NULL,
     @answerList AS DBO.AnswerList READONLY
   )
AS 
BEGIN
	BEGIN TRY
	DECLARE @isInstructor int, @CourseID int, @type int, @CorrectId int;

	-- get question type
	SELECT @type=typeID FROM Question WHERE ID=@QuestionID

	-- throw an error if question type not 'multi-choice'
	IF @type!=2
		THROW 51001, 'This question doesnt belong to "multi-choice" question type', 1;  
    
    -- get course id
    SELECT @CourseID = CourseID FROM QuestionPool WHERE QuestionID=@QuestionID

	--  check if this instructor teach this course 
	SET @isInstructor =  dbo.IsCourseInstrctor(@instrID, @CourseID);

    IF (@isInstructor=1)  -- if yes update the question
	BEGIN
		-- update question
	    IF @Question IS NOT NULL
		  UPDATE Question SET Question=@Question WHERE ID=@QuestionID

		IF EXISTS (SELECT 1 FROM @answerList)
		BEGIN
			-- delete existing choices 
			DELETE FROM Choices WHERE QuestionID = @QuestionID

			-- insert the given choices to choices table
			INSERT INTO Choices (answer, QuestionID) 
			SELECT Answer, @QuestionID  FROM @answerList
	 
			-- find the correct answer id and update question tuple to add it
			SELECT @CorrectId = C.ID
			FROM @answerList L JOIN Choices C ON C.answer=L.Answer
			WHERE L.true=1

			UPDATE QUESTION SET answer=@CorrectId WHERE ID=@QuestionID
		END
	END
	ELSE          -- if not => don't update 
		SELECT 'This instructor doesnt teach this course'
  END TRY
  BEGIN CATCH
     SELECT ERROR_MESSAGE();
  END CATCH
	 

END
GO

-- 6. generate auto exam 
CREATE PROC AutoQenerateExam
(
  @InstrID int,  
  @CourseID int,
  @TFNumber int, -- true or false questions number
  @MCNumber int, -- multi-choice questions number
  @Start VARCHAR(50), 
  @Time VARCHAR(5),
  @Degree decimal
)
AS
BEGIN
   DECLARE @isInstructor int, @End datetime,
           @tcount int = 0, @ccount int = 0, @SDate datetime,
		   @QuesID int, @ExamID int, @QDegree decimal;

   -- check if this instructor teach this course 
   SET @isInstructor =  dbo.IsCourseInstrctor(@instrID, @CourseID);

   IF @isInstructor=1  -- if yes delete the question
   BEGIN

     SET @SDate = CAST(@Start AS datetime);

     -- Calculate end time from start and total time
     SET @End = dbo.AddTime(@SDate, @Time);

	 -- insert new exam with exam state
     INSERT INTO Exam (CourseID, InstructorID, StartTime, EndTime, TotalTime, Degree, State) 
	 VALUES (@CourseID, @InstrID, @SDate, @End, @Time, @Degree, 'exam')	
	 SET @ExamID = SCOPE_IDENTITY();

	 -- calculate degree for each question
	 SET @QDegree = CONVERT(decimal(4,2),@Degree) / (@TFNumber+ @MCNumber);

	 -- insert random questions  
	 WHILE @tcount < @TFNumber OR @ccount < @MCNumber
	 BEGIN
	    -- select random question id from question poll
	    SELECT TOP(1) @QuesID=ID FROM QuestionPool 
		WHERE CourseID=@CourseID
		ORDER BY NEWID();
		
		-- if the selected question already exists -> skip this iteration
		IF EXISTS(SELECT * FROM ExamQuestions 
		          where QuestionID=@QuesID and ExamID=@ExamID)
			CONTINUE
		ELSE
		BEGIN
		   -- get the type of question
		   DECLARE @Type INT
		   SELECT @Type=typeID FROM Question WHERE ID=@QuesID;

		   IF @type=1 and @tcount<@TFNumber
			BEGIN
		      INSERT INTO ExamQuestions (ExamID, QuestionID, Degree) VALUES (@ExamID, @QuesID, @QDegree)
			  SET @tcount = @tcount+1
			END
		   ELSE IF @Type=2 AND @ccount<@MCNumber
			BEGIN
		      INSERT INTO ExamQuestions (ExamID, QuestionID, Degree) VALUES (@ExamID, @QuesID, @QDegree)
			  SET @ccount = @ccount+1
			END
		END
	 END
   END
   ELSE          -- if not => don't delete
     SELECT 'This instructor doesnt teach this course'
END
GO

-- 7. add exam manulay 
CREATE PROC AddExam
(
  @InstrID int,  
  @CourseID int,
  @Start VARCHAR(50), 
  @Time VARCHAR(5),
  @Degree decimal,
  @questionList AS DBO.QuestionList READONLY
)
AS
BEGIN
   DECLARE @isInstructor int, @End datetime, @SDate datetime, @ExamID int;

   -- check if this instructor teach this course 
   SET @isInstructor =  dbo.IsCourseInstrctor(@instrID, @CourseID);

   IF @isInstructor=1  -- if yes delete the question
   BEGIN

     SET @SDate = CAST(@Start AS datetime);

     -- Calculate end time from start and total time
     SET @End = dbo.AddTime(@SDate, @Time);

	 -- insert new exam with exam state
     INSERT INTO Exam (CourseID, InstructorID, StartTime, EndTime, TotalTime, Degree, State) 
	 VALUES (@CourseID, @InstrID, @SDate, @End, @Time, @Degree, 'exam')	
	 SET @ExamID = SCOPE_IDENTITY();

	 -- insert questions  
	 INSERT INTO ExamQuestions (ExamID, QuestionID, Degree)
	 SELECT @ExamID, quesID, degree FROM @questionList
   END
   ELSE          -- if not => don't delete
     SELECT 'This instructor doesnt teach this course'
END
GO

-- 8. assign exam to class
CREATE PROC AssignClassExam
(
  @InstrID int,  
  @ExamID int,
  @ClassID int
)
AS
BEGIN
	BEGIN TRY
		DECLARE @isInstructor int, @End datetime, @SDate datetime, @CourseID int 

		-- get exam course
		SELECT @CourseID=CourseID FROM Exam WHERE ID=@ExamID

		-- check if this class assign to this course
		IF NOT EXISTS (SELECT * FROM ClassCourse WHERE ClassID=@ClassID AND CourseID=@CourseID)
			THROW 51000, 'This class doesnt study this course', 1;  

		-- check if this instructor teach this course 
		SET @isInstructor =  dbo.IsCourseInstrctor(@instrID, @CourseID);

		IF @isInstructor != 1  
			THROW 51001, 'This instructor doesnt teach this course', 1;  

		INSERT INTO StudentExams (ExamID, StudentID)
		SELECT @ExamID, ID FROM Student WHERE ClassID = @ClassID
	END TRY
	BEGIN CATCH
	     SELECT ERROR_MESSAGE();
	END CATCH
END
GO

-- 9. Submit Student answer
CREATE PROC StudentExamAnswer
(
  @ExamID int,  
  @StudentID int,
  @answerList AS DBO.StudentAnswerList READONLY
)
AS
BEGIN
	BEGIN TRY
		-- check if this exam assign to this student
		IF NOT EXISTS (SELECT * FROM StudentExams WHERE StudentID=@StudentID AND ExamID=@ExamID)
			THROW 51000, 'This student doesnt has this exam', 1;  

		INSERT INTO StudentAnswers (StudentID, ExamID, QuestionID, Answer)
		SELECT @StudentID, @ExamID, quesID, answer FROM @answerList
	END TRY
	BEGIN CATCH
	     SELECT ERROR_MESSAGE();
	END CATCH
END
GO

-- 10. CHECK STUDENT ANSWER FOR SPECIFIC QUESTION
CREATE PROC CheckAnswer(@id int, @ExamID int)
AS
BEGIN
    DECLARE @deg int, @SA int, @CA int;

	SELECT @CA = Q.answer, @SA=SQ.Answer, @deg=E.Degree
	FROM Question Q, StudentAnswers SQ, ExamQuestions E
	WHERE Q.ID=SQ.QuestionID AND E.QuestionID=Q.ID  
	      AND SQ.ID=@id AND E.ExamID=@ExamID;

	IF @CA = @SA
	   UPDATE StudentAnswers SET Correct = @deg WHERE ID=@ID
	ELSE
	   UPDATE StudentAnswers SET Correct = 0 WHERE ID=@ID
END
GO

-- 11. Calculate exam result for student
CREATE PROC ExamResult(@examID int, @studentid int)
AS
BEGIN
    DECLARE @result int = 0

	SELECT @result= @result + ISNULL(Correct,0)
	FROM StudentAnswers 
	WHERE ExamID=@examID AND StudentID=@studentid;

	UPDATE StudentExams SET Result = @result WHERE ExamID=@examID AND StudentID=@studentid;
END
GO
---------------------------------------------------------------------------------------
---- >> triggers << ---- 

-- set exam result 
CREATE TRIGGER ExamCorrection
ON Exam
AFTER UPDATE
AS
BEGIN 
IF UPDATE([State])
	BEGIN
	    DECLARE @rowID int, @studentID int, @ExamID int ;

		-- get id of updated row
	    SELECT @ExamID= (SELECT ID FROM inserted);

	    -- get question data into temp table
	    SELECT * INTO  #Temp
        From   StudentAnswers WHERE ExamID = @ExamID;

		-- for each question check the correct answer for each table
		WHILE EXISTS(SELECT * FROM #Temp)
		BEGIN
		  SELECT TOP(1) @rowID=ID FROM #Temp
		  DELETE FROM #Temp WHERE (id = @rowID);

		  EXEC DBO.CheckAnswer @rowID, @ExamID
	    END
		-- drop temp table
	    DROP TABLE #Temp

	    -- get student exam data into temp table
	    SELECT * INTO   #Temp2
        From StudentExams WHERE ExamID = @ExamID

		-- for each student calculate his result
		WHILE EXISTS(SELECT * FROM #Temp2)
		BEGIN
		  SELECT TOP(1) @studentID=StudentID FROM #Temp2

		  DELETE FROM #Temp2 WHERE (StudentID = @studentID);

		  EXEC DBO.ExamResult @examID,  @studentID;
	    END
		-- drop temp table
	    DROP TABLE #Temp2
	END
END
GO
---------------------------------------------------------------------------------------
-- TEST

EXEC DBO.AddTrueFalseQues @QUESTION = 'EQUIVALENT TO is (more or less) the same as EQUAL TO.',
     @CourseID = 2, @ANSWER = 'T', @instrID=1;
----------
DECLARE @Choices DBO.AnswerList
INSERT INTO @Choices VALUES ('such, that', 1), ('such, so', 0),
('that, since', 0), ('that, that',0)
-- EXEC UpdateMultiChoiceQues 3,20,@answerList = @Choices;
EXEC AddMultiChoiceQues 1, 2,
'Cannon had __________ unique qualities _________ it was used widely in ancient times.',@Choices;

SELECT * FROM CourseQuestions 
SELECT * FROM Choices WHERE QuestionID=20 
SELECT * FROM dbo.GetCourseQuestions('Chemistry')

EXEC DeleteQuestion 3,19;

-- raise an error
EXEC UpdateTrueFalseQues 3,18,'Which acid is described as HOOCCOOH?','Oxalic Acid'

EXEC UpdateTrueFalseQues 1,1,'A RIVER is bigger than a STREAM','f'
-- update answer only
EXEC UpdateTrueFalseQues 1,1,@answer='t'
-- update question only
EXEC UpdateTrueFalseQues 1,1,'A RIVER is bigger than a STREAM.'

-------------------
EXEC AutoQenerateExam 1,2,3,3,'2021-3-3 09:00','2:30',18;
EXEC AutoQenerateExam 1,2,5,5,'2021-3-5 12:00','1:15',10;

-------------------
DECLARE @questions DBO.QuestionList
INSERT INTO @questions VALUES (12, 1), (14, 1),(16, 1), (20,1)
EXEC AddExam 3,3,'2021-3-5 10:00','00:20',4, @questions;


SELECT * FROM GetExamQuestions(1);
SELECT * FROM CourseExam
--------------------
EXEC AssignClassExam 1,1,1

SELECT * FROM StudentExams
SELECT * FROM Question
SELECT * FROM dbo.GetQuestionsChoices(25)
SELECT * FROM StudentAnswers

DECLARE @answers DBO.StudentAnswerList
INSERT INTO @answers VALUES (5, 1), (9, 1),(10, 1), (22,63), (25, 77), (26, 78)
EXEC StudentExamAnswer 1,3,@answers;

UPDATE Exam SET State='corrective' WHERE ID=1;