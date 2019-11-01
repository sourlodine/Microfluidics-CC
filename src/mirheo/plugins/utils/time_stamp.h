#pragma once

#include <mirheo/core/mirheo_state.h>

bool isTimeEvery(const MirState *state, int dumpEvery);
bool isTimeEvery(const MirState *state, real dumpEvery) = delete;

MirState::StepType getTimeStamp(const MirState *state, int dumpEvery);
MirState::StepType getTimeStamp(const MirState*, real) = delete;

