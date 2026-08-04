module PathTest exposing (tests)

import Expect
import Fuzz
import Schelm.Node.FileSystem.Path as Path
import Test exposing (Test, describe, fuzz, test)


tests : Test
tests =
    describe "cooperative paths"
        [ test "rejects traversal and separators" <|
            \_ ->
                [ [ "..", "x" ], [ "." ], [ "a/b" ], [ "a\\b" ], [] ]
                    |> List.all (\parts -> Result.toMaybe (Path.relativeFile parts) == Nothing)
                    |> Expect.equal True
        , fuzz (Fuzz.listOfLengthBetween 1 16 safeSegment) "accepted segments round-trip" <|
            \parts ->
                Path.relativeFile parts
                    |> Result.map Path.relativeSegments
                    |> Expect.equal (Ok parts)
        , test "cooperative roots are explicitly absolute" <|
            \_ ->
                case ( Path.cooperativeRoot "/root", Path.cooperativeRoot "relative" ) of
                    ( Ok _, Err Path.RootMustBeAbsolute ) ->
                        Expect.pass

                    _ ->
                        Expect.fail "unexpected root validation result"
        , test "friendly root and file recipes use the existing validators" <|
            \_ ->
                ( Path.root "/root" |> Result.map Path.rootString
                , Path.file "state.json" |> Result.map Path.relativeSegments
                , Path.fileAt [ "sessions", "current.json" ] |> Result.map Path.relativeSegments
                )
                    |> Expect.equal
                        ( Ok "/root"
                        , Ok [ "state.json" ]
                        , Ok [ "sessions", "current.json" ]
                        )
        , test "compatibility names retain identical results" <|
            \_ ->
                { root = Path.root "/root" |> Result.map Path.rootString
                , cooperativeRoot = Path.cooperativeRoot "/root" |> Result.map Path.rootString
                , fileAt = Path.fileAt [ "a", "b" ] |> Result.map Path.relativeSegments
                , relativeFile = Path.relativeFile [ "a", "b" ] |> Result.map Path.relativeSegments
                }
                    |> Expect.equal
                        { root = Ok "/root"
                        , cooperativeRoot = Ok "/root"
                        , fileAt = Ok [ "a", "b" ]
                        , relativeFile = Ok [ "a", "b" ]
                        }
        ]


safeSegment : Fuzz.Fuzzer String
safeSegment =
    Fuzz.map (\n -> "segment-" ++ String.fromInt (abs n)) Fuzz.int
