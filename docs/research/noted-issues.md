This document provides findings that are proven to be causing issues. This document is not the place for noting down the solution, only known mistakes.

- fpp is a gameFPPCameraComponent (an entIComponent), not an entity (entEntity).
- In REDengine / CET, components do not have an IsAttached() method. entities that does have IsAttached() hasn't confirmed / no proof yet.