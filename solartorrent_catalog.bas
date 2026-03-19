/* SolarTorrent Catalog Smart Contract
   Decentralized torrent catalog on DERO blockchain.
   
   Storage schema:
   - "owner"              : SC owner address (raw)
   - "deposit_amount"     : anti-spam deposit in atomic units (default 10000 = 0.1 DERO)
   - "torrent_count"      : total number of submissions (auto-increment ID)
   - "approved_count"     : total approved torrents
   
   Per-torrent keys (where {id} is a Uint64):
   - "t_{id}_hash"        : infohash (btih hex string)
   - "t_{id}_title"       : display title
   - "t_{id}_desc"        : description
   - "t_{id}_cat"         : category (software, ebook, audio, video, dataset, archive, other)
   - "t_{id}_lic"         : license (CC0, CC-BY, GPL-3.0, MIT, etc.)
   - "t_{id}_magnet"      : full magnet URI
   - "t_{id}_size"        : file size in bytes (0 if unknown)
   - "t_{id}_submitter"   : submitter address (raw)
   - "t_{id}_status"      : 0=pending, 1=approved, 2=rejected
   - "t_{id}_time"        : block timestamp at submission
   
   Entrypoints:
   - Initialize()                         : setup on install
   - SubmitTorrent(hash, title, desc, cat, lic, magnet, size) : submit + deposit
   - ApproveTorrent(id)                   : owner approves, refunds deposit
   - RejectTorrent(id)                    : owner rejects, deposit kept as fee
   - RemoveTorrent(id)                    : owner removes entry
   - SetDeposit(amount)                   : owner adjusts deposit amount
   - TransferOwnership(newowner)          : transfer SC ownership
   - ClaimOwnership()                     : new owner claims
   - Withdraw(amount)                     : owner withdraws accumulated fees
   - UpdateCode(code)                     : owner updates SC code
*/


// Initialize is called once when the SC is installed
Function Initialize() Uint64
10  STORE("owner", SIGNER())
20  STORE("deposit_amount", 10000)
30  STORE("torrent_count", 0)
40  STORE("approved_count", 0)
50  RETURN 0
End Function


// SubmitTorrent: anyone can submit a torrent entry with anti-spam deposit
// Requires ringsize 2 so SIGNER() is known
// Caller must send >= deposit_amount DERO with the transaction
Function SubmitTorrent(hash String, title String, desc String, cat String, lic String, magnet String, size Uint64) Uint64
10  DIM id as Uint64
20  DIM dep as Uint64
    // Validate deposit
30  LET dep = LOAD("deposit_amount")
40  IF DEROVALUE() >= dep THEN GOTO 60
50  RETURN 1
    // Validate required fields are not empty
60  IF STRLEN(hash) >= 1 THEN GOTO 80
70  RETURN 1
80  IF STRLEN(title) >= 1 THEN GOTO 100
90  RETURN 1
    // Get and increment torrent counter
100 LET id = LOAD("torrent_count")
110 STORE("torrent_count", id + 1)
    // Store all torrent metadata
120 STORE("t_" + id + "_hash", hash)
130 STORE("t_" + id + "_title", title)
140 STORE("t_" + id + "_desc", desc)
150 STORE("t_" + id + "_cat", cat)
160 STORE("t_" + id + "_lic", lic)
170 STORE("t_" + id + "_magnet", magnet)
180 STORE("t_" + id + "_size", size)
190 STORE("t_" + id + "_submitter", SIGNER())
200 STORE("t_" + id + "_status", 0)
210 STORE("t_" + id + "_time", BLOCK_TIMESTAMP())
220 RETURN 0
End Function


// ApproveTorrent: owner approves a pending torrent and refunds the deposit
Function ApproveTorrent(id Uint64) Uint64
10  DIM status as Uint64
20  DIM submitter as String
30  IF LOAD("owner") == SIGNER() THEN GOTO 50
40  RETURN 1
    // Check torrent exists and is pending (status == 0)
50  IF EXISTS("t_" + id + "_status") == 1 THEN GOTO 70
60  RETURN 1
70  LET status = LOAD("t_" + id + "_status")
80  IF status == 0 THEN GOTO 100
90  RETURN 1
    // Set status to approved
100 STORE("t_" + id + "_status", 1)
110 STORE("approved_count", LOAD("approved_count") + 1)
    // Refund deposit to submitter
120 LET submitter = LOAD("t_" + id + "_submitter")
130 SEND_DERO_TO_ADDRESS(submitter, LOAD("deposit_amount"))
140 RETURN 0
End Function


// RejectTorrent: owner rejects a pending torrent, deposit is kept as fee
Function RejectTorrent(id Uint64) Uint64
10  DIM status as Uint64
20  IF LOAD("owner") == SIGNER() THEN GOTO 40
30  RETURN 1
    // Check torrent exists and is pending
40  IF EXISTS("t_" + id + "_status") == 1 THEN GOTO 60
50  RETURN 1
60  LET status = LOAD("t_" + id + "_status")
70  IF status == 0 THEN GOTO 90
80  RETURN 1
    // Set status to rejected
90  STORE("t_" + id + "_status", 2)
100 RETURN 0
End Function


// RemoveTorrent: owner can remove any torrent entry (set status to 3=removed)
Function RemoveTorrent(id Uint64) Uint64
10  IF LOAD("owner") == SIGNER() THEN GOTO 30
20  RETURN 1
30  IF EXISTS("t_" + id + "_status") == 1 THEN GOTO 50
40  RETURN 1
50  STORE("t_" + id + "_status", 3)
60  IF LOAD("t_" + id + "_status") != 1 THEN GOTO 80
70  STORE("approved_count", LOAD("approved_count") - 1)
80  RETURN 0
End Function


// SetDeposit: owner adjusts the anti-spam deposit amount
Function SetDeposit(amount Uint64) Uint64
10  IF LOAD("owner") == SIGNER() THEN GOTO 30
20  RETURN 1
30  STORE("deposit_amount", amount)
40  RETURN 0
End Function


// TransferOwnership: standard DERO pattern
Function TransferOwnership(newowner String) Uint64
10  IF LOAD("owner") == SIGNER() THEN GOTO 30
20  RETURN 1
30  STORE("tmpowner", ADDRESS_RAW(newowner))
40  RETURN 0
End Function


// ClaimOwnership: new owner claims after TransferOwnership
Function ClaimOwnership() Uint64
10  IF LOAD("tmpowner") == SIGNER() THEN GOTO 30
20  RETURN 1
30  STORE("owner", SIGNER())
40  RETURN 0
End Function


// Withdraw: owner withdraws accumulated DERO fees
Function Withdraw(amount Uint64) Uint64
10  IF LOAD("owner") == SIGNER() THEN GOTO 30
20  RETURN 1
30  SEND_DERO_TO_ADDRESS(SIGNER(), amount)
40  RETURN 0
End Function


// UpdateCode: owner can update smart contract code
Function UpdateCode(code String) Uint64
10  IF LOAD("owner") == SIGNER() THEN GOTO 30
20  RETURN 1
30  UPDATE_SC_CODE(code)
40  RETURN 0
End Function
