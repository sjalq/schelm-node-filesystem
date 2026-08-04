module Schelm.Node.FileSystem.AtomicTextFixture exposing (replace)

{-| Test-only kernel fixture. Never a production dependency.

@docs replace

-}

import Elm.Kernel.SchelmAtomicTextFixture
import Task exposing (Task)


{-| Execute the instrumented replacement transaction.
-}
replace : String -> List String -> String -> Task { phase : String, error : { kind : String, code : String, message : String }, residue : List String } { durability : String, stage : String, error : { kind : String, code : String, message : String }, residue : List String }
replace =
    Elm.Kernel.SchelmAtomicTextFixture.replace
