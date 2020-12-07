/*
Example of Procedure:
*/


project "snaqvi Demo", {
    procedure "Hello Procedure", {
        step "Hello World",
            command : "echo Hello World from EF DSL!"
    }
}

