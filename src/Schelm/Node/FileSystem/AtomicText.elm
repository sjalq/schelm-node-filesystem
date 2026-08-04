module Schelm.Node.FileSystem.AtomicText exposing
    ( Cleanup(..)
    , CommitAcknowledgement(..)
    , CooperativeRoot
    , Durability(..)
    , DurabilityStage(..)
    , Error
    , ErrorKind(..)
    , FailurePhase(..)
    , PathError(..)
    , RelativeFile
    , ReplaceFailure
    , ReplaceResult(..)
    , Residue(..)
    , RootError(..)
    , cleanupResidue
    , cooperativeRoot
    , errorCode
    , errorKind
    , errorMessage
    , failureCleanup
    , failureCommit
    , failureError
    , failurePhase
    , relativeFile
    , relativeSegments
    , replace
    )

{-| A deliberately narrow Node 24/Linux API for replacing one complete UTF-8
text file. `CooperativeRoot` prevents accidental root mixing only. It is publicly
mintable and is not a security boundary. The destination parent must remain at
the same pathname, and exactly one process may write the destination, throughout
an operation.
-}

import Elm.Kernel.SchelmAtomicText
import Schelm.Node.FileSystem.Path as Path exposing (CooperativeRoot, PathError(..), RelativeFile, RootError(..))
import Task exposing (Task)


type ReplaceResult
    = RenameAcknowledged
        { durability : Durability
        , cleanup : Cleanup
        }


type CommitAcknowledgement
    = NoRenameAcknowledgement
    | RenameWasAcknowledged


type Durability
    = FileAndDirectorySyncAcknowledged
    | DurabilityUnconfirmed DurabilityStage Error


type DurabilityStage
    = OpeningParent
    | SyncingParent
    | ClosingParent


type Cleanup
    = CleanupAcknowledged
    | CleanupIncomplete (List Residue)


type Residue
    = TempMayRemain
    | TempDescriptorMayRemain
    | ParentDescriptorMayRemain


type ReplaceFailure
    = ReplaceFailure
        { commit : CommitAcknowledgement
        , phase : FailurePhase
        , error : Error
        , cleanup : Cleanup
        }


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


type Error
    = Error
        { kind : ErrorKind
        , code : Maybe String
        , message : String
        }


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


cooperativeRoot : String -> Result RootError CooperativeRoot
cooperativeRoot =
    Path.cooperativeRoot


relativeFile : List String -> Result PathError RelativeFile
relativeFile =
    Path.relativeFile


relativeSegments : RelativeFile -> List String
relativeSegments =
    Path.relativeSegments


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


errorKind : Error -> ErrorKind
errorKind (Error details) =
    details.kind


errorCode : Error -> Maybe String
errorCode (Error details) =
    details.code


errorMessage : Error -> String
errorMessage (Error details) =
    details.message


cleanupResidue : Cleanup -> List Residue
cleanupResidue cleanup =
    case cleanup of
        CleanupAcknowledged ->
            []

        CleanupIncomplete residue ->
            residue


failureCommit : ReplaceFailure -> CommitAcknowledgement
failureCommit (ReplaceFailure details) =
    details.commit


failurePhase : ReplaceFailure -> FailurePhase
failurePhase (ReplaceFailure details) =
    details.phase


failureError : ReplaceFailure -> Error
failureError (ReplaceFailure details) =
    details.error


failureCleanup : ReplaceFailure -> Cleanup
failureCleanup (ReplaceFailure details) =
    details.cleanup
