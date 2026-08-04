module Schelm.Node.FileSystem.Path exposing
    ( CooperativeRoot, RelativeFile, RootError(..), PathError(..)
    , root, cooperativeRoot, file, fileAt, relativeFile
    , relativeSegments, rootString
    , rootErrorMessage, pathErrorMessage
    )

{-| Validated roots and files for atomic text replacement.

Most callers can start with [`root`](#root), [`file`](#file), or
[`fileAt`](#fileAt). These values prevent accidental path mixing. They are not
authorization and do not defend against a hostile local process.

@docs CooperativeRoot, RelativeFile, RootError, PathError
@docs root, cooperativeRoot, file, fileAt, relativeFile
@docs relativeSegments, rootString
@docs rootErrorMessage, pathErrorMessage

-}


{-| A validated, application-owned absolute directory.

This value prevents accidentally mixing an unvalidated string into an operation.
It is publicly constructible and is not a security capability.

-}
type CooperativeRoot
    = CooperativeRoot String


{-| Why an application root could not be constructed.
-}
type RootError
    = RootMustBeAbsolute
    | RootContainsNul
    | RootHasTrailingSeparator


{-| A non-empty file path beneath a `CooperativeRoot`.

Each path segment is validated separately, so traversal and embedded separators
cannot be represented.

-}
type RelativeFile
    = RelativeFile (List String)


{-| Why a relative file path could not be constructed.
-}
type PathError
    = EmptyPath
    | EmptySegment
    | DotSegment
    | ParentSegment
    | ContainsNul
    | ContainsSeparator


{-| Validate an application-owned absolute root directory.

    root "/var/lib/my-app"

The directory must already be owned and kept at the same pathname by the
application while replacement runs.

-}
root : String -> Result RootError CooperativeRoot
root raw =
    if String.contains "\u{0000}" raw then
        Err RootContainsNul

    else if not (String.startsWith "/" raw) then
        Err RootMustBeAbsolute

    else if raw /= "/" && String.endsWith "/" raw then
        Err RootHasTrailingSeparator

    else
        Ok (CooperativeRoot raw)


{-| Compatibility name for [`root`](#root).
-}
cooperativeRoot : String -> Result RootError CooperativeRoot
cooperativeRoot =
    root


{-| Validate one filename beneath a root.

    file "daemon.json"

Use [`fileAt`](#fileAt) for a nested path.

-}
file : String -> Result PathError RelativeFile
file name =
    fileAt [ name ]


{-| Validate a non-empty file path from explicit segments.

    fileAt [ "sessions", "current.json" ]

Segments cannot be empty, `.`, `..`, contain NUL, or contain `/` or `\\`.

-}
fileAt : List String -> Result PathError RelativeFile
fileAt parts =
    case parts of
        [] ->
            Err EmptyPath

        _ ->
            validateSegments parts
                |> Result.map (always (RelativeFile parts))


{-| Compatibility name for [`fileAt`](#fileAt).
-}
relativeFile : List String -> Result PathError RelativeFile
relativeFile =
    fileAt


validateSegments : List String -> Result PathError ()
validateSegments parts =
    case parts of
        [] ->
            Ok ()

        part :: rest ->
            validateSegment part
                |> Result.andThen (always (validateSegments rest))


validateSegment : String -> Result PathError ()
validateSegment part =
    if String.isEmpty part then
        Err EmptySegment

    else if part == "." then
        Err DotSegment

    else if part == ".." then
        Err ParentSegment

    else if String.contains "\u{0000}" part then
        Err ContainsNul

    else if String.contains "/" part || String.contains "\\" part then
        Err ContainsSeparator

    else
        Ok ()


{-| Return the validated path segments. Useful for serialization and diagnostics.
-}
relativeSegments : RelativeFile -> List String
relativeSegments (RelativeFile parts) =
    parts


{-| Return the validated absolute root string.
-}
rootString : CooperativeRoot -> String
rootString (CooperativeRoot raw) =
    raw


{-| Explain a root construction error in plain English.
-}
rootErrorMessage : RootError -> String
rootErrorMessage problem =
    case problem of
        RootMustBeAbsolute ->
            "The root must be an absolute path."

        RootContainsNul ->
            "The root cannot contain a NUL character."

        RootHasTrailingSeparator ->
            "The root cannot end with a slash, unless it is the filesystem root /."


{-| Explain a file construction error in plain English.
-}
pathErrorMessage : PathError -> String
pathErrorMessage problem =
    case problem of
        EmptyPath ->
            "A file path needs at least one segment."

        EmptySegment ->
            "File path segments cannot be empty."

        DotSegment ->
            "Use explicit file path segments instead of ."

        ParentSegment ->
            "A file path cannot traverse to its parent with .."

        ContainsNul ->
            "A file path segment cannot contain a NUL character."

        ContainsSeparator ->
            "Pass each directory and filename as a separate segment; a segment cannot contain / or \\."
