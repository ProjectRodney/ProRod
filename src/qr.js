// QR code rendering for the administration page (bundled; no runtime CDN dependency).
import QRCode from 'qrcode';
export default function qrDataUrl(text,scale=6){return QRCode.toDataURL(text,{errorCorrectionLevel:'M',margin:4,scale});}
