port module AtomicTextFixtureWorker exposing (main)

import Json.Encode as Encode
import Platform
import Schelm.Node.FileSystem.AtomicTextFixture as Fixture
import Task


port report : Encode.Value -> Cmd msg


type Msg
    = Finished (Result { phase : String, error : { kind : String, code : String, message : String }, residue : List String } { durability : String, stage : String, error : { kind : String, code : String, message : String }, residue : List String })


type alias Flags =
    { root : String, segments : List String, text : String }


main : Program Flags () Msg
main =
    Platform.worker
        { init = \flags -> ( (), Task.attempt Finished (Fixture.replace flags.root flags.segments flags.text) )
        , update = update
        , subscriptions = always Sub.none
        }


update : Msg -> () -> ( (), Cmd Msg )
update (Finished result) model =
    ( model
    , report
        (Encode.object
            [ ( "ok"
              , Encode.bool
                    (case result of
                        Ok _ ->
                            True

                        Err _ ->
                            False
                    )
              )
            ]
        )
    )
