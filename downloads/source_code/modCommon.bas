Attribute VB_Name = "modCommon"
Option Explicit

' Independently designed and implemented by the author on synthetic data.
' Not an export of any employer's workbook.
' Business rules, data design and acceptance testing by the author;
' AI assisted coding and documentation.

' False preserves pre-existing formula rows below the current import range.
' Risk: when the current month has fewer rows than the prior month, those residual
' formula rows may remain in a pivot-table source range. Set True only after testing
' the target workbook's formula and pivot-table boundaries.
Public Const CLEAR_LEFTOVER As Boolean = False

Public Function Cfg(ByVal r As Long) As String
    Cfg = Trim$(CStr(ThisWorkbook.Worksheets("Setting").Cells(r, 2).Value))
End Function

Public Function FindBook(ByVal key As String) As Workbook
    Dim wb As Workbook
    For Each wb In Workbooks
        If InStr(1, wb.Name, key, vbTextCompare) > 0 Then
            Set FindBook = wb
            Exit Function
        End If
    Next wb
End Function

Public Function FileNameOf(ByVal p As String) As String
    FileNameOf = Mid$(p, InStrRev(p, Application.PathSeparator) + 1)
End Function

Public Function ColLetter(ByVal c As Long) As String
    ColLetter = Split(Cells(1, c).Address(True, False), "$" )(0)
End Function

Public Function FindHeaders(ws As Worksheet, ByRef hr As Long, ByRef sc As Long) As Boolean
    Dim k As Range, c As Long, v As Variant
    Set k = ws.UsedRange.Find(Cfg(6), LookIn:=xlValues, LookAt:=xlWhole)
    If k Is Nothing Then Exit Function
    For c = k.Column To 1 Step -1
        v = ws.Cells(k.Row, c).Value
        If Not IsError(v) Then
            If CStr(v) = Cfg(7) Then hr = k.Row: sc = c: FindHeaders = True: Exit Function
        End If
    Next c
End Function

Public Function LatestFile(ByVal folder As String, ByVal prefix As String) As String
    Dim fso As Object, f As Object, best As Date, nm As String
    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FolderExists(folder) Then Exit Function
    For Each f In fso.GetFolder(folder).Files
        nm = LCase$(f.Name)
        If Left$(nm, Len(prefix)) = LCase$(prefix) And Left$(nm, 2) <> "~$" Then
            If Right$(nm, 4) = ".xls" Or Right$(nm, 5) = ".xlsx" Or Right$(nm, 5) = ".xlsm" Then
                If f.DateLastModified > best Then best = f.DateLastModified: LatestFile = f.Path
            End If
        End If
    Next f
End Function

Public Function LatestTxt(ByVal folder As String, ByVal prefix As String) As String
    Dim fso As Object, best As Date, bestPath As String
    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FolderExists(folder) Then Exit Function
    ScanFolder fso.GetFolder(folder), prefix, best, bestPath
    LatestTxt = bestPath
End Function

Private Sub ScanFolder(ByVal fd As Object, ByVal prefix As String, ByRef best As Date, ByRef bestPath As String)
    Dim f As Object, sf As Object, nm As String
    For Each f In fd.Files
        nm = LCase$(f.Name)
        If Left$(nm, Len(prefix)) = LCase$(prefix) And Right$(nm, 4) = ".txt" And Left$(nm, 2) <> "~$" Then
            If f.DateLastModified > best Then best = f.DateLastModified: bestPath = f.Path
        End If
    Next f
    For Each sf In fd.SubFolders
        ScanFolder sf, prefix, best, bestPath
    Next sf
End Sub

Public Function StampFromName(ByVal nm As String, ByRef d As Date) As Boolean
    Dim re As Object, m As Object, y As Long, mo As Long, dd As Long
    Dim hh As Long, mm As Long, ss As Long
    Set re = CreateObject("VBScript.RegExp")
    re.Pattern = "(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})"
    If Not re.Test(nm) Then Exit Function
    Set m = re.Execute(nm)(0)
    y = CLng(m.SubMatches(0)): mo = CLng(m.SubMatches(1)): dd = CLng(m.SubMatches(2))
    hh = CLng(m.SubMatches(3)): mm = CLng(m.SubMatches(4)): ss = CLng(m.SubMatches(5))
    If mo < 1 Or mo > 12 Or dd < 1 Or dd > 31 Or hh > 23 Or mm > 59 Or ss > 59 Then Exit Function
    d = DateSerial(y, mo, dd) + TimeSerial(hh, mm, ss)
    If Month(d) <> mo Then Exit Function
    StampFromName = True
End Function

Public Function GetLabelValue(ws As Worksheet, ByVal lastRow As Long, ByVal label As String, ByRef out As Variant) As Boolean
    Dim r As Range, j As Long, v As Variant
    If lastRow < 1 Or Len(label) = 0 Then Exit Function
    Set r = ws.Range(ws.Cells(1, 1), ws.Cells(lastRow, 20)).Find(label, LookIn:=xlValues, LookAt:=xlWhole)
    If r Is Nothing Then Exit Function
    For j = 1 To 5
        v = r.Offset(0, j).Value
        If Not IsError(v) Then
            If Len(Trim$(CStr(v))) > 0 Then out = v: GetLabelValue = True: Exit Function
        End If
    Next j
End Function

Public Function PutStamp(ws As Worksheet, ByVal hr As Long, ByVal sc As Long, _
                         ByVal hasDate As Boolean, ByVal sDate As Variant, _
                         ByVal hasTime As Boolean, ByVal sTime As Variant, ByVal stamp As Date) As String
    Dim rng As Range, lbl As Range, dVal As Double, tVal As Double, ok As Boolean
    Dim srcD As String, srcT As String
    If hr <= 1 Then PutStamp = "Date/time area unavailable": Exit Function
    Set rng = ws.Range(ws.Cells(1, sc), ws.Cells(hr - 1, sc + 2))
    Set lbl = rng.Find(Cfg(9), LookIn:=xlValues, LookAt:=xlWhole)
    If lbl Is Nothing Then
        srcD = "date label not found"
    Else
        ok = False
        If hasDate And IsDate(sDate) Then dVal = Int(CDbl(CDate(sDate))): ok = True
        If Not ok Then dVal = Int(CDbl(stamp))
        With lbl.Offset(0, 1)
            If .NumberFormat = "General" Then .NumberFormat = "yyyy/m/d"
            .Value = dVal
        End With
        srcD = IIf(ok, "date from source", "date from file modified time")
    End If
    Set lbl = rng.Find(Cfg(10), LookIn:=xlValues, LookAt:=xlWhole)
    If lbl Is Nothing Then
        srcT = "time label not found"
    Else
        ok = False
        If hasTime And IsDate(sTime) Then tVal = CDbl(CDate(sTime)) - Int(CDbl(CDate(sTime))): ok = True
        If Not ok Then tVal = CDbl(stamp) - Int(CDbl(stamp))
        With lbl.Offset(0, 1)
            If .NumberFormat = "General" Then .NumberFormat = "h:mm"
            .Value = tVal
        End With
        srcT = IIf(ok, "time from source", "time from file modified time")
    End If
    PutStamp = srcD & " / " & srcT
End Function