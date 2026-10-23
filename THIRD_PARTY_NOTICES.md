# Reused transport implementation

USB FunctionFS C/JNI and the Kotlin root helper/pipe adapter are adapted from [cmwen/codex-micro-tablet](https://github.com/cmwen/codex-micro-tablet/tree/d2a3cf0eb56798f931afa9088fc710ca73ee17f7), revision d2a3cf0eb56798f931afa9088fc710ca73ee17f7, MIT License, Copyright (c) 2024 cmwen. The full MIT license is preserved in LICENSE.

This port parameterizes native report ID and size, replaces vendor framing with standard pen reports, removes audio and unused configfs HID mutation, retains physical device USB identity, and adds foreign FunctionFS ownership refusal. Backend divergence is intentional and recorded; no change to the Codex Micro repository is required.
