pub mod framing;
pub mod state;
pub mod upload;
pub mod download;

#[allow(unused_imports)]
pub use framing::{
    FRAME_MAGIC, FRAME_ID_SIZE, FRAME_OFFSET_SIZE, FRAME_SEQ_SIZE, FRAME_FLAGS_SIZE,
    FRAME_HEADER_SIZE, TransferFrameHeader, parse_frame_header,
};
#[allow(unused_imports)]
pub use state::{
    TransferState, UploadSession, UPLOAD_SESSIONS, DOWNLOAD_TASKS,
    state_path, part_path, write_state, cleanup_partial,
};
pub use upload::{
    handle_transfer_init, handle_transfer_cancel, handle_transfer_chunk_raw,
    cleanup_client_uploads,
};
pub use download::handle_download_init;
