module Schelm.Node.FileSystem.AtomicText exposing
    ( CooperativeRoot, RelativeFile, RootError, PathError
    , cooperativeRoot, relativeFile, relativeSegments
    , ReplaceResult(..), ReplaceFailure, CommitAcknowledgement(..), Durability(..), DurabilityStage(..)
    , Cleanup(..), Residue(..), FailurePhase(..), Error, ErrorKind(..)
    , replace, cleanupResidue
    , errorCode, errorKind, errorMessage
    , failureCleanup, failureCommit, failureError, failurePhase
    )

{-| A deliberately narrow Node 24/Linux API for replacing one complete UTF-8
text file. `CooperativeRoot` prevents accidental root mixing only. It is publicly
mintable and is not a security boundary. The destination parent must remain at
the same pathname, and exactly one process may write the destination, throughout
an operation.

@docs CooperativeRoot, RelativeFile, RootError, PathError
@docs cooperativeRoot, relativeFile, relativeSegments
@docs ReplaceResult, ReplaceFailure, CommitAcknowledgement, Durability, DurabilityStage
@docs Cleanup, Residue, FailurePhase, Error, ErrorKind
@docs replace, cleanupResidue
@docs errorCode, errorKind, errorMessage
@docs failureCleanup, failureCommit, failureError, failurePhase

-}

import Elm.Kernel.SchelmAtomicText
import Schelm.Node.FileSystem.Path as Path
import Task exposing (Task)


{-| CooperativeRoot is part of the typed atomic replacement contract.
-}
type alias CooperativeRoot =
    Path.CooperativeRoot


{-| RelativeFile is part of the typed atomic replacement contract.
-}
type alias RelativeFile =
    Path.RelativeFile


{-| RootError is part of the typed atomic replacement contract.
-}
type alias RootError =
    Path.RootError


{-| PathError is part of the typed atomic replacement contract.
-}
type alias PathError =
    Path.PathError


{-| ReplaceResult is part of the typed atomic replacement contract.
-}
type ReplaceResult
    = RenameAcknowledged
        { durability : Durability
        , cleanup : Cleanup
        }


{-| CommitAcknowledgement is part of the typed atomic replacement contract.
-}
type CommitAcknowledgement
    = NoRenameAcknowledgement
    | RenameWasAcknowledged


{-| Durability is part of the typed atomic replacement contract.
-}
type Durability
    = FileAndDirectorySyncAcknowledged
    | DurabilityUnconfirmed DurabilityStage Error


{-| DurabilityStage is part of the typed atomic replacement contract.
-}
type DurabilityStage
    = OpeningParent
    | SyncingParent
    | ClosingParent


{-| Cleanup is part of the typed atomic replacement contract.
-}
type Cleanup
    = CleanupAcknowledged
    | CleanupIncomplete (List Residue)


{-| Residue is part of the typed atomic replacement contract.
-}
type Residue
    = TempMayRemain
    | TempDescriptorMayRemain
    | ParentDescriptorMayRemain


{-| ReplaceFailure is part of the typed atomic replacement contract.
-}
type ReplaceFailure
    = ReplaceFailure
        { commit : CommitAcknowledgement
        , phase : FailurePhase
        , error : Error
        , cleanup : Cleanup
        }


{-| FailurePhase is part of the typed atomic replacement contract.
-}
type FailurePhase
    = Validating
    | CheckingParent
    | OpeningTemp
    | WritingTemp
    | SyncingTemp
    | ClosingTemp
    | Renaming
    | OpeningParentAfterRename
    | SyncingParentAfterRename
    | ClosingParentAfterRename
    | CleaningTemp


{-| Error is part of the typed atomic replacement contract.
-}
type Error
    = Error
        { kind : ErrorKind
        , code : Maybe String
        , message : String
        }


{-| ErrorKind is part of the typed atomic replacement contract.
-}
type ErrorKind
    = NotFound
    | PermissionDenied
    | NotDirectory
    | IsDirectory
    | SymlinkRejected
    | InvalidInput
    | PathTooLong
    | TooManyOpenFiles
    | IoFailure
    | Unsupported
    | UnknownFailure


type alias RawError =
    { kind : String, code : String, message : String }


type alias RawOutcome =
    { durability : String
    , stage : String
    , error : RawError
    , residue : List String
    }


type alias RawFailure =
    { phase : String
    , error : RawError
    , residue : List String
    }


{-| cooperativeRoot is part of the typed atomic replacement contract.
-}
cooperativeRoot : String -> Result RootError CooperativeRoot
cooperativeRoot =
    Path.cooperativeRoot


{-| relativeFile is part of the typed atomic replacement contract.
-}
relativeFile : List String -> Result PathError RelativeFile
relativeFile =
    Path.relativeFile


{-| relativeSegments is part of the typed atomic replacement contract.
-}
relativeSegments : RelativeFile -> List String
relativeSegments =
    Path.relativeSegments


{-| replace is part of the typed atomic replacement contract.
-}
replace : CooperativeRoot -> RelativeFile -> String -> Task ReplaceFailure ReplaceResult
replace root file text =
    Elm.Kernel.SchelmAtomicText.replace (Path.rootString root) (Path.relativeSegments file) text
        |> Task.mapError decodeFailure
        |> Task.map decodeOutcome


decodeOutcome : RawOutcome -> ReplaceResult
decodeOutcome raw =
    let
        cleanup =
            decodeCleanup raw.residue
    in
    if raw.durability == "durable" then
        RenameAcknowledged
            { durability = FileAndDirectorySyncAcknowledged
            , cleanup = cleanup
            }

    else
        RenameAcknowledged
            { durability = DurabilityUnconfirmed (decodeDurabilityStage raw.stage) (decodeError raw.error)
            , cleanup = cleanup
            }


decodeFailure : RawFailure -> ReplaceFailure
decodeFailure raw =
    ReplaceFailure
        { commit = NoRenameAcknowledgement
        , phase = decodeFailurePhase raw.phase
        , error = decodeError raw.error
        , cleanup = decodeCleanup raw.residue
        }


decodeCleanup : List String -> Cleanup
decodeCleanup raw =
    case List.filterMap decodeResidue raw of
        [] ->
            CleanupAcknowledged

        residue ->
            CleanupIncomplete residue


decodeResidue : String -> Maybe Residue
decodeResidue raw =
    case raw of
        "temp" ->
            Just TempMayRemain

        "temp-fd" ->
            Just TempDescriptorMayRemain

        "parent-fd" ->
            Just ParentDescriptorMayRemain

        _ ->
            Nothing


decodeDurabilityStage : String -> DurabilityStage
decodeDurabilityStage raw =
    case raw of
        "opening-parent" ->
            OpeningParent

        "closing-parent" ->
            ClosingParent

        _ ->
            SyncingParent


decodeFailurePhase : String -> FailurePhase
decodeFailurePhase raw =
    case raw of
        "validating" ->
            Validating

        "checking-parent" ->
            CheckingParent

        "opening-temp" ->
            OpeningTemp

        "writing-temp" ->
            WritingTemp

        "syncing-temp" ->
            SyncingTemp

        "closing-temp" ->
            ClosingTemp

        "renaming" ->
            Renaming

        "opening-parent" ->
            OpeningParentAfterRename

        "syncing-parent" ->
            SyncingParentAfterRename

        "closing-parent" ->
            ClosingParentAfterRename

        _ ->
            CleaningTemp


decodeError : RawError -> Error
decodeError raw =
    Error
        { kind = decodeErrorKind raw.kind
        , code =
            if String.isEmpty raw.code then
                Nothing

            else
                Just raw.code
        , message = raw.message
        }


decodeErrorKind : String -> ErrorKind
decodeErrorKind raw =
    case raw of
        "not-found" ->
            NotFound

        "permission-denied" ->
            PermissionDenied

        "not-directory" ->
            NotDirectory

        "is-directory" ->
            IsDirectory

        "symlink-rejected" ->
            SymlinkRejected

        "invalid-input" ->
            InvalidInput

        "path-too-long" ->
            PathTooLong

        "too-many-open-files" ->
            TooManyOpenFiles

        "io-failure" ->
            IoFailure

        "unsupported" ->
            Unsupported

        _ ->
            UnknownFailure


{-| errorKind is part of the typed atomic replacement contract.
-}
errorKind : Error -> ErrorKind
errorKind (Error details) =
    details.kind


{-| errorCode is part of the typed atomic replacement contract.
-}
errorCode : Error -> Maybe String
errorCode (Error details) =
    details.code


{-| errorMessage is part of the typed atomic replacement contract.
-}
errorMessage : Error -> String
errorMessage (Error details) =
    details.message


{-| cleanupResidue is part of the typed atomic replacement contract.
-}
cleanupResidue : Cleanup -> List Residue
cleanupResidue cleanup =
    case cleanup of
        CleanupAcknowledged ->
            []

        CleanupIncomplete residue ->
            residue


{-| failureCommit is part of the typed atomic replacement contract.
-}
failureCommit : ReplaceFailure -> CommitAcknowledgement
failureCommit (ReplaceFailure details) =
    details.commit


{-| failurePhase is part of the typed atomic replacement contract.
-}
failurePhase : ReplaceFailure -> FailurePhase
failurePhase (ReplaceFailure details) =
    details.phase


{-| failureError is part of the typed atomic replacement contract.
-}
failureError : ReplaceFailure -> Error
failureError (ReplaceFailure details) =
    details.error


{-| failureCleanup is part of the typed atomic replacement contract.
-}
failureCleanup : ReplaceFailure -> Cleanup
failureCleanup (ReplaceFailure details) =
    details.cleanup
