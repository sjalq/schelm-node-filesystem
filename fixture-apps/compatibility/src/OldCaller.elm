port module OldCaller exposing (main)

import Json.Encode as Encode
import Platform
import Schelm.Node.FileSystem.AtomicText as AtomicText
import Task


port report : Encode.Value -> Cmd msg


type Msg
    = Finished (Result AtomicText.ReplaceFailure AtomicText.ReplaceResult)


type alias Flags =
    { root : String, segments : List String, text : String }


main : Program Flags () Msg
main =
    Platform.worker
        { init =
            \flags ->
                case ( AtomicText.cooperativeRoot flags.root, AtomicText.relativeFile flags.segments ) of
                    ( Ok root, Ok file ) ->
                        ( (), AtomicText.replace root file flags.text |> Task.attempt Finished )

                    _ ->
                        ( (), report (Encode.string "invalid") )
        , update = \_ model -> ( model, report (Encode.string "settled") )
        , subscriptions = always Sub.none
        }
