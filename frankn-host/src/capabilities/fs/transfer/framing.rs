pub const FRAME_MAGIC: u8 = 0x01;
pub const FRAME_ID_SIZE: usize = 36;
pub const FRAME_OFFSET_SIZE: usize = 8;
pub const FRAME_SEQ_SIZE: usize = 4;
pub const FRAME_FLAGS_SIZE: usize = 1;
pub const FRAME_HEADER_SIZE: usize =
    1 + FRAME_ID_SIZE + FRAME_OFFSET_SIZE + FRAME_SEQ_SIZE + FRAME_FLAGS_SIZE;

pub const FLAG_FINAL: u8 = 0x02;
pub const FLAG_ACK_REQUESTED: u8 = 0x04;

pub struct TransferFrameHeader {
    pub transfer_id: String,
    pub offset: u64,
    pub seq: u32,
    pub flags: u8,
}

pub fn parse_frame_header(data: &[u8]) -> Option<TransferFrameHeader> {
    if data.len() < FRAME_HEADER_SIZE || data.first().copied() != Some(FRAME_MAGIC) {
        return None;
    }

    let id_bytes = &data[1..1 + FRAME_ID_SIZE];
    let transfer_id = String::from_utf8_lossy(id_bytes)
        .trim_matches(char::from(0))
        .to_string();
    let offset_start = 1 + FRAME_ID_SIZE;
    let seq_start = offset_start + FRAME_OFFSET_SIZE;
    let flags_index = seq_start + FRAME_SEQ_SIZE;

    Some(TransferFrameHeader {
        transfer_id,
        offset: u64::from_be_bytes(data[offset_start..seq_start].try_into().ok()?),
        seq: u32::from_be_bytes(data[seq_start..flags_index].try_into().ok()?),
        flags: data[flags_index],
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(id: &str, offset: u64, seq: u32, flags: u8) -> Vec<u8> {
        let mut data = Vec::with_capacity(FRAME_HEADER_SIZE);
        data.push(FRAME_MAGIC);
        let mut id_bytes = [0u8; FRAME_ID_SIZE];
        id_bytes[..id.len()].copy_from_slice(id.as_bytes());
        data.extend_from_slice(&id_bytes);
        data.extend_from_slice(&offset.to_be_bytes());
        data.extend_from_slice(&seq.to_be_bytes());
        data.push(flags);
        data
    }

    #[test]
    fn transfer_frame_layout_is_stable_and_decodes_fields() {
        let data = frame("550e8400-e29b-41d4-a716-446655440000", 4096, 42, FLAG_FINAL);

        assert_eq!(FRAME_HEADER_SIZE, 50);
        assert_eq!(data.len(), FRAME_HEADER_SIZE);

        let header = parse_frame_header(&data).unwrap();
        assert_eq!(header.transfer_id, "550e8400-e29b-41d4-a716-446655440000");
        assert_eq!(header.offset, 4096);
        assert_eq!(header.seq, 42);
        assert_eq!(header.flags, FLAG_FINAL);
    }

    #[test]
    fn transfer_frame_decoder_rejects_short_or_invalid_frames() {
        assert!(parse_frame_header(&[]).is_none());
        assert!(parse_frame_header(&vec![0; FRAME_HEADER_SIZE]).is_none());
        assert!(parse_frame_header(&vec![FRAME_MAGIC; FRAME_HEADER_SIZE - 1]).is_none());
    }
}
