// Independently designed and implemented by the author on synthetic data.
// Not an export of any employer's workbook.
// Business rules, data design and acceptance testing by the author; AI assisted coding and documentation.
let
    RootFolder = "<ROOT_PATH>\AP",
    Files = Folder.Files(RootFolder),
    Candidates = Table.SelectRows(Files, each
        Text.StartsWith([Name], "AP Payment Detail", Comparer.OrdinalIgnoreCase)
        and Text.Lower([Extension]) = ".txt"
        and ([Attributes]?[Hidden]? <> true)),
    Latest = if Table.RowCount(Candidates)=0 then error "No AP input file found"
             else Table.First(Table.Sort(Candidates, {{"Date modified", Order.Descending}})),
    Raw = Csv.Document(Latest[Content], [Delimiter=",", Columns=35, Encoding=65001, QuoteStyle=QuoteStyle.None]),
    Headers = Table.PromoteHeaders(Raw, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {
        {"Payment Date", type date}, {"GL Date", type date}, {"Entered Currency", type text},
        {"Account Number", type text}, {"Vendor ID", type text},
        {"Payment Amount", type number}, {"Payment Amount JPY", type number}, {"Payment Rate", type number}
    }, "en-US"),
    Grouped = Table.Group(Typed,
        {"Payment Date","GL Date","Entered Currency","Account Number","Vendor ID","Payment Method","Payment Terms","Payment Group"},
        {{"Payment Amount", each List.Sum([Payment Amount]), type nullable number},
         {"Payment Amount JPY", each List.Sum([Payment Amount JPY]), type nullable number}}),
    SourceFile = Table.AddColumn(Grouped, "Source File", each Latest[Name], type text)
in
    SourceFile