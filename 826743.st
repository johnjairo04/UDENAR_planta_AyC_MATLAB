PROGRAM test
  VAR
    Start AT %MW0 : INT;
    Stop AT %MW1 : INT;
    Emerg AT %MW2 : INT;
  END_VAR
  VAR
    Start_bool : BOOL;
    Stop_bool : BOOL;
    Emerg_bool : BOOL;
  END_VAR
  VAR
    LED1 AT %QX0.2 : BOOL;
    LED2 AT %QX0.3 : BOOL;
  END_VAR
  VAR
    INT_TO_BOOL11_OUT : BOOL;
    INT_TO_BOOL3_OUT : BOOL;
    INT_TO_BOOL7_OUT : BOOL;
  END_VAR

  INT_TO_BOOL11_OUT := INT_TO_BOOL(Start);
  Start_bool := INT_TO_BOOL11_OUT;
  LED1 := Start_bool;
  INT_TO_BOOL3_OUT := INT_TO_BOOL(Stop);
  Stop_bool := INT_TO_BOOL3_OUT;
  LED2 := Emerg_bool OR Stop_bool;
  INT_TO_BOOL7_OUT := INT_TO_BOOL(Emerg);
  Emerg_bool := INT_TO_BOOL7_OUT;
END_PROGRAM


CONFIGURATION Config0

  RESOURCE Res0 ON PLC
    TASK task0(INTERVAL := T#20ms,PRIORITY := 0);
    PROGRAM instance0 WITH task0 : test;
  END_RESOURCE
END_CONFIGURATION
