module Schelm.Node.FileSystem.AtomicText exposing
    ( CooperativeRoot, RelativeFile, RootError, PathError
    , root, cooperativeRoot, file, fileAt, relativeFile, relativeSegments
    , rootErrorMessage, pathErrorMessage
    , replaceDurably, DurableReplaceError(..), requireDurable, durableErrorMessage
    , ReplaceResult(..), ReplaceFailure, CommitAcknowledgement(..), Durability(..), DurabilityStage(..)
    , Cleanup(..), Residue(..), FailurePhase(..), Error, ErrorKind(..)
    , replace, cleanupResidue
    , errorCode, errorKind, errorMessage, errorKindMessage
    , failureCleanup, failureCommit, failureError, failurePhase
    )

{-| Replace one complete UTF-8 text file atomically on Node 24/Linux.

The common path is: choose an application-owned root, choose a file beneath it,
and ask for acknowledged durability.

    save : AtomicText.CooperativeRoot -> AtomicText.RelativeFile -> String -> Task AtomicText.DurableReplaceError ()
    save appRoot stateFile text =
        AtomicText.replaceDurably appRoot stateFile text

Use [`replace`](#replace) when recovery needs the full distinction between
installation acknowledgement, durability, and cleanup.

`CooperativeRoot` prevents accidental root mixing only. It is publicly mintable
and is not a security boundary. The application must keep the destination parent
at the same pathname, and exactly one process may write the destination,
throughout an operation. The supported platform is Node 24.4.1, Linux x86\_64,
and ext4.

@docs CooperativeRoot, RelativeFile, RootError, PathError
@docs root, cooperativeRoot, file, fileAt, relativeFile, relativeSegments
@docs rootErrorMessage, pathErrorMessage
@docs replaceDurably, DurableReplaceError, requireDurable, durableErrorMessage
@docs ReplaceResult, ReplaceFailure, CommitAcknowledgement, Durability, DurabilityStage
@docs Cleanup, Residue, FailurePhase, Error, ErrorKind
@docs replace, cleanupResidue
@docs errorCode, errorKind, errorMessage, errorKindMessage
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


{-| The replacement was installed. Durability and cleanup remain explicit.
-}
type ReplaceResult
    = RenameAcknowledged
        { durability : Durability
        , cleanup : Cleanup
        }


{-| Whether a successful rename callback was observed.

`NoRenameAcknowledgement` does not prove that the physical rename did not occur.

-}
type CommitAcknowledgement
    = NoRenameAcknowledgement
    | RenameWasAcknowledged


{-| Whether file and containing-directory sync were acknowledged.
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


{-| Whether cleanup of temporary names and owned descriptors was acknowledged.
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


{-| A recovery-shaped failure from [`replaceDurably`](#replaceDurably).

Each constructor says whether installation was acknowledged and whether the new
text is proven durable. Do not retry blindly: an unacknowledged replacement may
still have physically occurred.

-}
type DurableReplaceError
    = ReplacementNotAcknowledged ReplaceFailure
    | ReplacementInstalledButDurabilityUnconfirmed DurabilityStage Error Cleanup
    | ReplacementDurableButCleanupIncomplete (List Residue)


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


{-| Validate an application-owned absolute root directory.
-}
root : String -> Result RootError CooperativeRoot
root =
    Path.root


{-| Compatibility name for [`root`](#root).
-}
cooperativeRoot : String -> Result RootError CooperativeRoot
cooperativeRoot =
    Path.cooperativeRoot


{-| Validate one filename beneath a root.
-}
file : String -> Result PathError RelativeFile
file =
    Path.file


{-| Validate a nested file path from explicit segments.
-}
fileAt : List String -> Result PathError RelativeFile
fileAt =
    Path.fileAt


{-| Compatibility name for [`fileAt`](#fileAt).
-}
relativeFile : List String -> Result PathError RelativeFile
relativeFile =
    Path.relativeFile


{-| Return the validated segments for serialization or diagnostics.
-}
relativeSegments : RelativeFile -> List String
relativeSegments =
    Path.relativeSegments


{-| Explain a root construction error in plain English.
-}
rootErrorMessage : RootError -> String
rootErrorMessage =
    Path.rootErrorMessage


{-| Explain a file construction error in plain English.
-}
pathErrorMessage : PathError -> String
pathErrorMessage =
    Path.pathErrorMessage


{-| Replace the whole file and succeed only when installation, durability, and
cleanup have all been acknowledged.

This is the recommended recipe for application state whose owner treats any
uncertain outcome as a fail-closed condition. The error says whether the
replacement was unacknowledged, installed without confirmed durability, or
fully durable with cleanup residue.

-}
replaceDurably : CooperativeRoot -> RelativeFile -> String -> Task DurableReplaceError ()
replaceDurably appRoot target text =
    replace appRoot target text
        |> Task.mapError ReplacementNotAcknowledged
        |> Task.andThen (requireDurable >> resultToTask)


{-| Require acknowledged durability and cleanup from an advanced result.

This pure classifier is useful when an application persists or transports the
advanced result before deciding whether to proceed.

-}
requireDurable : ReplaceResult -> Result DurableReplaceError ()
requireDurable (RenameAcknowledged details) =
    case ( details.durability, details.cleanup ) of
        ( FileAndDirectorySyncAcknowledged, CleanupAcknowledged ) ->
            Ok ()

        ( FileAndDirectorySyncAcknowledged, CleanupIncomplete residue ) ->
            Err (ReplacementDurableButCleanupIncomplete residue)

        ( DurabilityUnconfirmed stage problem, cleanup ) ->
            Err (ReplacementInstalledButDurabilityUnconfirmed stage problem cleanup)


resultToTask : Result error value -> Task error value
resultToTask result =
    case result of
        Ok value ->
            Task.succeed value

        Err problem ->
            Task.fail problem


{-| The advanced operation. It exposes installation acknowledgement, durability,
and cleanup separately for applications with custom recovery policy.
-}
replace : CooperativeRoot -> RelativeFile -> String -> Task ReplaceFailure ReplaceResult
replace appRoot target text =
    Elm.Kernel.SchelmAtomicText.replace (Path.rootString appRoot) (Path.relativeSegments target) text
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


{-| Classify an operation error without parsing text.
-}
errorKind : Error -> ErrorKind
errorKind (Error details) =
    details.kind


{-| errorCode is part of the typed atomic replacement contract.
-}
errorCode : Error -> Maybe String
errorCode (Error details) =
    details.code


{-| Return the bounded diagnostic message supplied by the operation boundary.
Branch on [`errorKind`](#errorKind), not this text.
-}
errorMessage : Error -> String
errorMessage (Error details) =
    details.message


{-| Explain an error kind in stable plain English.
-}
errorKindMessage : ErrorKind -> String
errorKindMessage kind =
    case kind of
        NotFound ->
            "The root or containing directory was not found."

        PermissionDenied ->
            "The application does not have permission to replace this file."

        NotDirectory ->
            "A parent path is not a directory."

        IsDirectory ->
            "The destination is a directory, not a text file."

        SymlinkRejected ->
            "A symbolic link was found where this operation requires a stable directory or file."

        InvalidInput ->
            "The text or path is not valid for atomic text replacement."

        PathTooLong ->
            "The root or file path is too long for this platform."

        TooManyOpenFiles ->
            "The process or system has no file handles available. Close other work and retry after inspecting the destination."

        IoFailure ->
            "The operating system could not complete the file operation. Inspect the destination before retrying."

        Unsupported ->
            "This operation is not supported on the current platform or filesystem."

        UnknownFailure ->
            "The file operation failed for an unclassified reason. Inspect the destination before retrying."


{-| Explain a durable replacement failure without hiding its recovery state.
-}
durableErrorMessage : DurableReplaceError -> String
durableErrorMessage problem =
    case problem of
        ReplacementNotAcknowledged _ ->
            "Replacement was not acknowledged. It may still have occurred; inspect the destination before retrying."

        ReplacementInstalledButDurabilityUnconfirmed _ operationError _ ->
            "Replacement was installed, but durability was not confirmed. " ++ errorKindMessage (errorKind operationError)

        ReplacementDurableButCleanupIncomplete _ ->
            "Replacement is durable, but cleanup was not fully acknowledged. Do not rewrite the file merely to retry cleanup."


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
