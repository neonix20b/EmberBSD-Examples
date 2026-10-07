# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.18)
project(ember_gnuradio_channel LANGUAGES CXX)
find_package(Gnuradio 3.10.12.0 EXACT CONFIG REQUIRED
  COMPONENTS blocks fft filter analog digital channels)
add_executable(ember-radio-channel channel.cpp)
target_compile_features(ember-radio-channel PRIVATE cxx_std_17)
target_compile_options(ember-radio-channel PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(ember-radio-channel PRIVATE
  gnuradio::gnuradio-runtime gnuradio::gnuradio-blocks
  gnuradio::gnuradio-filter gnuradio::gnuradio-digital gnuradio::gnuradio-channels)
enable_testing()
add_test(NAME radio-corrected COMMAND ember-radio-channel)
add_test(NAME radio-uncorrected-control COMMAND ember-radio-channel --no-correction)
set_tests_properties(radio-corrected radio-uncorrected-control PROPERTIES TIMEOUT 45)
foreach(case corrected uncorrected-control)
  set(run "${CMAKE_CURRENT_BINARY_DIR}/run-${case}")
  file(MAKE_DIRECTORY "${run}/prefs" "${run}/cache" "${run}/state" "${run}/volk")
  # An existing empty configuration prevents VOLK falling back to HOME.
  file(WRITE "${run}/volk/volk_config" "")
  set_tests_properties(radio-${case} PROPERTIES ENVIRONMENT
    "GR_PREFS_PATH=${run}/prefs;GR_CACHE_PATH=${run}/cache;GR_STATE_PATH=${run}/state;VOLK_CONFIGPATH=${run}")
endforeach()
