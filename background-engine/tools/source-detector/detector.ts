import { SourceInspector, InspectionResult } from '../../src/main/sourceInspector.js';

/**
 * STANDALONE SOURCE DETECTOR & DEEP PROTOCOL ANALYZER
 * Separate utility for technical inspection, DOM reverse-engineering,
 * and WebSocket frame discovery without loading the live Broadcast Engine.
 */
export async function runStandaloneDetection(url: string) {
  console.log('===============================================================');
  console.log('  🔍 DEKA SOURCE DETECTOR — STANDALONE COMPANION TOOL');
  console.log('===============================================================');
  console.log(`[Detector] Target URL: ${url}`);

  const inspector = new SourceInspector('persist:operator_browser_session');
  try {
    const result: InspectionResult = await inspector.inspectUrl(url);
    console.log('\n--- KẾT QUẢ PHÂN TÍCH NGUỒN THỰC TẾ ---');
    console.log(`Tiêu đề trang: ${result.title}`);
    console.log(`Đã có phiên đăng nhập: ${result.hasAuthenticatedSession ? 'CÓ (AUTHENTICATED)' : 'CHƯA CÓ'}`);
    console.log(`Tổng số nguồn phát hiện: ${result.candidates.length}`);

    result.candidates.forEach((cand, idx) => {
      console.log(`\n[${idx + 1}] NGUỒN: ${cand.name}`);
      console.log(`    Loại: ${cand.type}`);
      console.log(`    Phân loại: ${cand.classification}`);
      console.log(`    Độ tin cậy: ${(cand.confidence * 100).toFixed(0)}%`);
      console.log(`    Đề xuất tích hợp: ${cand.recommendation}`);
      console.log(`    Lý do: ${cand.reason}`);
      if (cand.details.url) console.log(`    URL / Endpoint: ${cand.details.url}`);
    });

    console.log('\n===============================================================');
    console.log('  HOÀN TẤT PHÂN TÍCH');
    console.log('===============================================================');
    return result;
  } catch (err: any) {
    console.error('[Detector] Phân tích thất bại:', err.message);
    throw err;
  } finally {
    inspector.destroy();
  }
}

// Support direct command line execution: node dist/tools/detector.js <url>
if (process.argv[2]) {
  runStandaloneDetection(process.argv[2]).then(() => process.exit(0)).catch(() => process.exit(1));
}
