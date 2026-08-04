module Schelm.Node.FileSystem.Path exposing
    ( CooperativeRoot
    , PathError(..)
    , RelativeFile
    , RootError(..)
    , cooperativeRoot
    , relativeFile
    , relativeSegments
    , rootString
    )

{-| Pure cooperative path values. These prevent accidental path mixing; they are
not authorization and do not defend against a hostile local process.
-}


type CooperativeRoot
    = CooperativeRoot String


type RootError
    = RootMustBeAbsolute
    | RootContainsNul
    | RootHasTrailingSeparator


type RelativeFile
    = RelativeFile (List String)


type PathError
    = EmptyPath
    | EmptySegment
    | DotSegment
    | ParentSegment
    | ContainsNul
    | ContainsSeparator


cooperativeRoot : String -> Result RootError CooperativeRoot
cooperativeRoot raw =
    if String.contains "\u{0000}" raw then
        Err RootContainsNul

    else if not (String.startsWith "/" raw) then
        Err RootMustBeAbsolute

    else if raw /= "/" && String.endsWith "/" raw then
        Err RootHasTrailingSeparator

    else
        Ok (CooperativeRoot raw)


relativeFile : List String -> Result PathError RelativeFile
relativeFile parts =
    case parts of
        [] ->
            Err EmptyPath

        _ ->
            validateSegments parts
                |> Result.map (always (RelativeFile parts))


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


relativeSegments : RelativeFile -> List String
relativeSegments (RelativeFile parts) =
    parts


rootString : CooperativeRoot -> String
rootString (CooperativeRoot raw) =
    raw
