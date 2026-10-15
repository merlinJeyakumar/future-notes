# Read-only Office parser. Pinned official release; no Office installation or
# runtime download is required on the destination computer.
include(FetchContent)
if(NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64")
  message(FATAL_ERROR "The Office preview bundle currently targets Windows x64.")
endif()
FetchContent_Declare(future_notes_office
  URL "https://github.com/yfedoseev/office_oxide/releases/download/v0.1.15/native-windows-x86_64.zip"
  URL_HASH "SHA256=00541bb8965f1a29ba1a56a90e6f1ecef1c25121a2480cc015046f2cd452f89f"
)
FetchContent_GetProperties(future_notes_office)
if(NOT future_notes_office_POPULATED)
  FetchContent_Populate(future_notes_office)
endif()
install(FILES "${future_notes_office_SOURCE_DIR}/lib/office_oxide.dll"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../licenses/office-oxide-MIT.txt"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses" COMPONENT Runtime)
# The PDFium plugin includes its upstream license and third-party notices.
install(DIRECTORY "${CMAKE_BINARY_DIR}/pdfium/chromium%2F7520/licenses/"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/pdfium" COMPONENT Runtime)
install(FILES "${CMAKE_BINARY_DIR}/pdfium/chromium%2F7520/LICENSE"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/pdfium" COMPONENT Runtime)
