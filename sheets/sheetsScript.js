const SHEET_NAME  = "Expenses";
const FILE_ID     = "1ijzDHV281Fhw3rRdHmTC1ORFhpLV-4k0urpoH69eGXw";
const TIMEZONE    = "Europe/London";
// Set this in Apps Script editor → Project Settings → Script Properties
// Key: APP_SECRET  Value: (same value you put in the iOS app Settings → Secret)
const SECRET_PROP = "APP_SECRET";

// Column indices (0-based)
const COL_DATE     = 0;
const COL_AMOUNT   = 1;
const COL_CURRENCY = 2;
const COL_CATEGORY = 3;
const COL_NAME     = 4;
const COL_TX_ID    = 5;

// ---------------------------------------------------------------------------
// GET — return all rows as JSON
// ---------------------------------------------------------------------------

function doGet(e) {
  try {
    const sheet = getSheet();
    const data  = sheet.getDataRange().getValues();

    const rows = data.map((row, i) => ({
      rowIndex: i + 1,  // 1-based, matches sheet row number
      date:     formatCell(row[COL_DATE]),
      amount:   row[COL_AMOUNT]   ? row[COL_AMOUNT].toString()   : "",
      currency: row[COL_CURRENCY] ? row[COL_CURRENCY].toString() : "",
      category: row[COL_CATEGORY] ? row[COL_CATEGORY].toString() : "",
      name:     row[COL_NAME]     ? row[COL_NAME].toString()     : "",
      txId:     row[COL_TX_ID]    ? row[COL_TX_ID].toString()    : ""
    }));

    return json({ rows });
  } catch (err) {
    return json({ error: err.message });
  }
}

// ---------------------------------------------------------------------------
// POST — dispatch on action field
//
// Single payload shapes:
//   { action: "upsert", txId, name, amount, currency, category, cardOrPass }
//   { action: "delete", txId }
//
// Batch payload shape:
//   { action: "batch", items: [ { action, ...fields }, ... ] }
// ---------------------------------------------------------------------------

function doPost(e) {
  if (!isAuthorised(e)) {
    return json({ error: "Unauthorised" });
  }

  try {
    const body   = JSON.parse(e.postData.contents);
    const action = body.action || "upsert";

    if (action === "batch") {
      return handleBatch(body);
    } else if (action === "delete") {
      return handleDelete(body);
    } else if (action === "patchRow") {
      return handlePatchRow(body);
    } else {
      return handleUpsert(body);
    }
  } catch (err) {
    return json({ error: err.message });
  }
}

// ---------------------------------------------------------------------------
// Batch — process multiple upsert/delete operations in one request.
// Reads the sheet once, applies all changes, then writes back in bulk.
// ---------------------------------------------------------------------------

function handleBatch(body) {
  const items = body.items;
  if (!Array.isArray(items) || items.length === 0) {
    return json({ error: "items array is required and must not be empty" });
  }

  const sheet  = getSheet();
  const now    = Utilities.formatDate(new Date(), TIMEZONE, "dd/MM/yyyy HH:mm:ss");
  // Read all existing data once
  const allData = sheet.getDataRange().getValues();

  // Build a txId → row-index (1-based) map for fast lookup
  const txIdMap = {};
  for (let i = 0; i < allData.length; i++) {
    const id = allData[i][COL_TX_ID].toString();
    if (id) txIdMap[id] = i + 1;
  }

  const results  = [];
  const toAppend = []; // rows to insert after processing deletes/updates

  for (const item of items) {
    const action = item.action || "upsert";

    if (action === "delete") {
      const { txId } = item;
      if (!txId) { results.push({ ok: false, error: "txId required", item }); continue; }
      const rowIndex = txIdMap[txId];
      if (!rowIndex) { results.push({ ok: true, action: "not_found", txId }); continue; }
      sheet.deleteRow(rowIndex);
      // Rebuild map after deletion (row numbers shift down by 1 for all rows below)
      const deleted = rowIndex;
      for (const key in txIdMap) {
        if (txIdMap[key] > deleted) txIdMap[key]--;
      }
      delete txIdMap[txId];
      results.push({ ok: true, action: "deleted", txId });

    } else {
      // upsert
      const { txId, name, amount, currency, category, cardOrPass } = item;
      if (!name)   { results.push({ ok: false, error: "name required",   txId }); continue; }
      if (!amount) { results.push({ ok: false, error: "amount required", txId }); continue; }
      if (!txId)   { results.push({ ok: false, error: "txId required"        }); continue; }

      const rowData = [now, amount, currency || "GBP", category || "", name, txId];
      const rowIndex = txIdMap[txId];

      if (rowIndex) {
        // Update in place — preserve original date
        const existingDate = sheet.getRange(rowIndex, COL_DATE + 1).getValue();
        if (existingDate instanceof Date) {
          rowData[COL_DATE] = Utilities.formatDate(existingDate, TIMEZONE, "dd/MM/yyyy HH:mm:ss");
        } else if (existingDate) {
          rowData[COL_DATE] = existingDate.toString();
        }
        sheet.getRange(rowIndex, 1, 1, rowData.length).setValues([rowData]);
        results.push({ ok: true, action: "updated", txId });
      } else {
        toAppend.push(rowData);
        results.push({ ok: true, action: "inserted", txId });
      }
    }
  }

  // Append all new rows in one operation
  if (toAppend.length > 0) {
    const lastRow = sheet.getLastRow();
    sheet.getRange(lastRow + 1, 1, toAppend.length, toAppend[0].length).setValues(toAppend);
  }

  return json({ ok: true, results });
}

// ---------------------------------------------------------------------------
// Upsert — update existing row if txId found, otherwise append
// ---------------------------------------------------------------------------

function handleUpsert(body) {
  const { txId, name, amount, currency, category, cardOrPass } = body;

  if (!name)   return json({ error: "name is required" });
  if (!amount) return json({ error: "amount is required" });
  if (!txId)   return json({ error: "txId is required" });

  const sheet   = getSheet();
  const now     = Utilities.formatDate(new Date(), TIMEZONE, "dd/MM/yyyy HH:mm:ss");
  const rowData = [now, amount, currency || "GBP", category || "", name, txId];
  const rowIndex = findRowByTxId(sheet, txId);

  if (rowIndex > 0) {
    // Update existing row — preserve original date, update everything else
    const existingDate = sheet.getRange(rowIndex, COL_DATE + 1).getValue();
    if (existingDate instanceof Date) {
      rowData[COL_DATE] = Utilities.formatDate(existingDate, TIMEZONE, "dd/MM/yyyy HH:mm:ss");
    } else if (existingDate) {
      rowData[COL_DATE] = existingDate.toString();
    } else {
      rowData[COL_DATE] = now;
    }
    sheet.getRange(rowIndex, 1, 1, rowData.length).setValues([rowData]);
  } else {
    sheet.appendRow(rowData);
  }

  return json({ ok: true, action: rowIndex > 0 ? "updated" : "inserted", txId });
}

// ---------------------------------------------------------------------------
// PatchRow — write a txId into a specific row that previously had none
// ---------------------------------------------------------------------------

function handlePatchRow(body) {
  const { rowIndex, txId } = body;
  if (!rowIndex || !txId) return json({ error: "rowIndex and txId are required" });

  const sheet = getSheet();
  sheet.getRange(rowIndex, COL_TX_ID + 1).setValue(txId);
  return json({ ok: true, action: "patched", rowIndex, txId });
}

// ---------------------------------------------------------------------------
// Delete — remove the row matching txId
// ---------------------------------------------------------------------------

function handleDelete(body) {
  const { txId } = body;
  if (!txId) return json({ error: "txId is required" });

  const sheet    = getSheet();
  const rowIndex = findRowByTxId(sheet, txId);

  if (rowIndex < 0) return json({ ok: true, action: "not_found", txId });

  sheet.deleteRow(rowIndex);
  return json({ ok: true, action: "deleted", txId });
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

// Returns true if no secret is configured (open) or the header matches.
// Note: doGet is intentionally unauthenticated — Google's redirect strips
// custom headers on GET requests before they reach the script.
function isAuthorised(e) {
  const configured = PropertiesService.getScriptProperties().getProperty(SECRET_PROP) || "";
  if (!configured) return true;
  const provided = (e.headers && (e.headers["X-App-Secret"] || e.headers["x-app-secret"])) || "";
  return provided === configured;
}

function getSheet() {
  return SpreadsheetApp.openById(FILE_ID).getSheetByName(SHEET_NAME);
}

function findRowByTxId(sheet, txId) {
  const values = sheet.getDataRange().getValues();
  for (let i = 0; i < values.length; i++) {
    if (values[i][COL_TX_ID].toString() === txId) return i + 1; // 1-based
  }
  return -1;
}

// Safely serialize a date cell to ISO 8601 UTC so iOS can parse it unambiguously.
// Handles four cases Sheets produces:
//   1. Native Date object (cell formatted as Date/DateTime)
//   2. Plain string "d/M/yyyy HH:mm:ss" or "dd/MM/yyyy HH:mm:ss" (stored as text)
//   3. Plain string "d/M/yyyy" (date only, stored as text)
//   4. Any other value — returned as-is
function formatCell(value) {
  if (!value) return "";

  // Helper: emit a GAS Date as ISO 8601 UTC (avoids toISOString() timezone quirks)
  function toUTCIso(d) {
    return Utilities.formatDate(d, "UTC", "yyyy-MM-dd'T'HH:mm:ss'Z'");
  }

  if (value instanceof Date) return toUTCIso(value);

  // Accept 1- or 2-digit day and month
  const m = value.toString().match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{2}):(\d{2}):(\d{2}))?$/);
  if (m) {
    const [, dd, mm, yyyy, hh = "00", min = "00", ss = "00"] = m;
    const isoStr = `${yyyy}-${mm.padStart(2,"0")}-${dd.padStart(2,"0")} ${hh}:${min}:${ss}`;
    const parsed = Utilities.parseDate(isoStr, TIMEZONE, "yyyy-MM-dd HH:mm:ss");
    if (parsed) return toUTCIso(parsed);
  }

  return value.toString();
}

function json(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}
