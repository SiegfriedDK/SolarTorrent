/* SolarTorrent Catalog Smart Contract v2
   Decentralized torrent catalog on DERO blockchain
   with community-driven validation/invalidation system.

   === STORAGE SCHEMA ===

   Global keys:
   - "owner"              : SC owner address (emergency powers)
   - "deposit_amount"     : anti-spam deposit in atomic units (default 10000 = 0.1 DERO)
   - "torrent_count"      : auto-increment submission ID
   - "approved_count"     : total community-approved torrents
   - "removed_count"      : total community-removed torrents

   Per-torrent keys (where {id} is a Uint64):
   - "t_{id}_hash"        : infohash (btih hex string)
   - "t_{id}_title"       : display title
   - "t_{id}_desc"        : description
   - "t_{id}_cat"         : category (movies, tvshows, animes, music, games, ebooks, softwares, other)
   - "t_{id}_magnet"      : full magnet URI
   - "t_{id}_size"        : file size in bytes (0 if unknown)
   - "t_{id}_submitter"   : submitter address (raw)
   - "t_{id}_status"      : 0=pending, 1=approved, 2=community-removed, 3=owner-removed
   - "t_{id}_time"        : block timestamp at submission
   - "t_{id}_valcount"    : number of validation votes
   - "t_{id}_invalcount"  : number of invalidation votes

   Per-vote keys (one vote per address per torrent):
   - "t_{id}_vote_{addr}" : 1=validated, 2=invalidated (prevents double voting)
   - "t_{id}_reason_{addr}" : invalidation reason string

   === THRESHOLDS ===
   - Auto-APPROVE : valcount >= 20 AND valcount > 5 * invalcount
                    → refund 0.1 DERO deposit to submitter, status → 1
   - Auto-REMOVE  : invalcount >= 10 AND invalcount > 5 * valcount
                    → send 0.1 DERO deposit to SC owner, status → 2

   === ENTRYPOINTS ===
   - Initialize()
   - SubmitTorrent(hash, title, desc, cat, magnet, size)
   - ValidateTorrent(id)
   - InvalidateTorrent(id, reason)
   - DonateTorrent(id)                  : send DERO to torrent submitter
   - RemoveTorrent(id)                  : owner emergency removal
   - SetDeposit(amount)                 : owner adjusts deposit
   - TransferOwnership(newowner)
   - ClaimOwnership()
   - Withdraw(amount)                   : owner withdraws accumulated fees
   - UpdateCode(code)
*/


Function Initialize() Uint64
10  STORE("owner", SIGNER())
20  STORE("deposit_amount", 10000)
30  STORE("torrent_count", 0)
40  STORE("approved_count", 0)
50  STORE("removed_count", 0)
60  RETURN 0
End Function


// SubmitTorrent: anyone can submit with anti-spam deposit
// Status starts at 0 (pending community vote)
Function SubmitTorrent(hash String, title String, desc String, cat String, magnet String, size Uint64) Uint64
10  DIM id as Uint64
20  DIM dep as Uint64
30  LET dep = LOAD("deposit_amount")
40  IF DEROVALUE() >= dep THEN GOTO 60
50  RETURN 1
60  IF STRLEN(hash) >= 1 THEN GOTO 80
70  RETURN 1
80  IF STRLEN(title) >= 1 THEN GOTO 100
90  RETURN 1
100 LET id = LOAD("torrent_count")
110 STORE("torrent_count", id + 1)
120 STORE("t_" + id + "_hash", hash)
130 STORE("t_" + id + "_title", title)
140 STORE("t_" + id + "_desc", desc)
150 STORE("t_" + id + "_cat", cat)
160 STORE("t_" + id + "_magnet", magnet)
170 STORE("t_" + id + "_size", size)
180 STORE("t_" + id + "_submitter", SIGNER())
190 STORE("t_" + id + "_status", 0)
200 STORE("t_" + id + "_time", BLOCK_TIMESTAMP())
210 STORE("t_" + id + "_valcount", 0)
220 STORE("t_" + id + "_invalcount", 0)
230 RETURN 0
End Function


// ValidateTorrent: community member confirms torrent matches description
// Requires ringsize 2 (SIGNER known). One vote per address per torrent.
// If thresholds are met, auto-approves and refunds deposit.
Function ValidateTorrent(id Uint64) Uint64
10  DIM votekey as String
20  DIM valcount, invalcount, status as Uint64
30  DIM submitter as String
    // Check torrent exists and is still pending
40  IF EXISTS("t_" + id + "_status") == 1 THEN GOTO 60
50  RETURN 1
60  LET status = LOAD("t_" + id + "_status")
70  IF status == 0 THEN GOTO 90
80  RETURN 1
    // Check voter has not already voted on this torrent
90  LET votekey = "t_" + id + "_vote_" + SIGNER()
100 IF EXISTS(votekey) == 0 THEN GOTO 120
110 RETURN 1
    // Record the validation vote
120 STORE(votekey, 1)
130 LET valcount = LOAD("t_" + id + "_valcount") + 1
140 STORE("t_" + id + "_valcount", valcount)
    // Check auto-approve threshold: valcount >= 20 AND valcount > 5 * invalcount
150 LET invalcount = LOAD("t_" + id + "_invalcount")
160 IF valcount >= 20 THEN GOTO 180
170 RETURN 0
180 IF valcount > 5 * invalcount THEN GOTO 200
190 RETURN 0
    // Threshold met: approve torrent and refund deposit to submitter
200 STORE("t_" + id + "_status", 1)
210 STORE("approved_count", LOAD("approved_count") + 1)
220 LET submitter = LOAD("t_" + id + "_submitter")
230 SEND_DERO_TO_ADDRESS(submitter, LOAD("deposit_amount"))
240 RETURN 0
End Function


// InvalidateTorrent: community member flags torrent as non-conforming
// reason must be: "mismatch", "pornography", or "violence"
// If thresholds are met, auto-removes and sends deposit to SC owner.
Function InvalidateTorrent(id Uint64, reason String) Uint64
10  DIM votekey, reasonkey as String
20  DIM valcount, invalcount, status as Uint64
    // Validate reason is one of the allowed values
30  IF reason == "mismatch" THEN GOTO 70
40  IF reason == "pornography" THEN GOTO 70
50  IF reason == "violence" THEN GOTO 70
60  RETURN 1
    // Check torrent exists and is still pending
70  IF EXISTS("t_" + id + "_status") == 1 THEN GOTO 90
80  RETURN 1
90  LET status = LOAD("t_" + id + "_status")
100 IF status == 0 THEN GOTO 120
110 RETURN 1
    // Check voter has not already voted on this torrent
120 LET votekey = "t_" + id + "_vote_" + SIGNER()
130 IF EXISTS(votekey) == 0 THEN GOTO 150
140 RETURN 1
    // Record the invalidation vote and reason
150 STORE(votekey, 2)
160 LET reasonkey = "t_" + id + "_reason_" + SIGNER()
170 STORE(reasonkey, reason)
180 LET invalcount = LOAD("t_" + id + "_invalcount") + 1
190 STORE("t_" + id + "_invalcount", invalcount)
    // Check auto-remove threshold: invalcount >= 10 AND invalcount > 5 * valcount
200 LET valcount = LOAD("t_" + id + "_valcount")
210 IF invalcount >= 10 THEN GOTO 230
220 RETURN 0
230 IF invalcount > 5 * valcount THEN GOTO 250
240 RETURN 0
    // Threshold met: remove torrent and send deposit to SC owner as penalty
250 STORE("t_" + id + "_status", 2)
260 STORE("removed_count", LOAD("removed_count") + 1)
270 SEND_DERO_TO_ADDRESS(LOAD("owner"), LOAD("deposit_amount"))
280 RETURN 0
End Function


// DonateTorrent: send DERO to the submitter of a torrent
// Caller sends DERO with the transaction, SC forwards it to submitter
Function DonateTorrent(id Uint64) Uint64
10  DIM submitter as String
20  DIM amount as Uint64
    // Check torrent exists
30  IF EXISTS("t_" + id + "_submitter") == 1 THEN GOTO 50
40  RETURN 1
    // Check that some DERO was sent
50  LET amount = DEROVALUE()
60  IF amount >= 1 THEN GOTO 80
70  RETURN 1
    // Forward the full amount to the submitter
80  LET submitter = LOAD("t_" + id + "_submitter")
90  SEND_DERO_TO_ADDRESS(submitter, amount)
100 RETURN 0
End Function


// RemoveTorrent: owner emergency removal (bypasses community vote)
Function RemoveTorrent(id Uint64) Uint64
10  IF LOAD("owner") == SIGNER() THEN GOTO 30
20  RETURN 1
30  IF EXISTS("t_" + id + "_status") == 1 THEN GOTO 50
40  RETURN 1
50  STORE("t_" + id + "_status", 3)
60  RETURN 0
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
