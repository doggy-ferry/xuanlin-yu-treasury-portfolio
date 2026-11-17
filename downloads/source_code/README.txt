Treasury Technology / Finance Transformation - Source Code

Independently designed and implemented by the author on synthetic data. Not an export of any employer's workbook.

Business rules, data design and acceptance testing were performed by the author; AI assisted coding and documentation. All paths use <ROOT_PATH>, and all fields and identifiers are generic. Review source-specific schemas before production use. Import .bas modules into an .xlsm copy and paste .pq scripts into Power Query Advanced Editor.

Implemented controls: header comparison, row checks, AR company-code check, formula-column extension, pivot-table refresh where coded, and date/time stamps where coded.

CLEAR_LEFTOVER defaults to False. If a current month contains fewer rows than the prior month, residual formula rows below the current range may remain in a pivot-table source. Change this option only after testing the target workbook's formula and pivot-table boundaries.

AP header comparison intentionally runs to nSrc - 1 because the Query appends a final Source File column for traceability.

Automation boundary: the code can identify contradictions covered by its rules; it cannot prove that source data is true.
