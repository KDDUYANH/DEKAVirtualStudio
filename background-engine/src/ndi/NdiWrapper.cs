using System;
using System.IO;
using System.Runtime.InteropServices;

namespace BackgroundEngine.Ndi
{
    public static class NdiWrapper
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
        public struct NDIlib_send_create_t
        {
            public string p_ndi_name;
            public string? p_groups;
            [MarshalAs(UnmanagedType.I1)]
            public bool clock_video;
            [MarshalAs(UnmanagedType.I1)]
            public bool clock_audio;
        }

        public enum NDIlib_FourCC_video_type_e : uint
        {
            NDIlib_FourCC_video_type_BGRA = 0x41524742,
            NDIlib_FourCC_video_type_BGRX = 0x58524742,
            NDIlib_FourCC_video_type_RGBA = 0x41424752,
            NDIlib_FourCC_video_type_RGBX = 0x58424752,
            NDIlib_FourCC_video_type_UYVY = 0x59565955
        }

        public enum NDIlib_frame_format_type_e : int
        {
            NDIlib_frame_format_type_progressive = 1,
            NDIlib_frame_format_type_interleaved = 2,
            NDIlib_frame_format_type_field_0 = 3,
            NDIlib_frame_format_type_field_1 = 4
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct NDIlib_video_frame_v2_t
        {
            public int xres;
            public int yres;
            public NDIlib_FourCC_video_type_e FourCC;
            public int frame_rate_N;
            public int frame_rate_D;
            public float picture_aspect_ratio;
            public NDIlib_frame_format_type_e frame_format_type;
            public long timecode;
            public IntPtr p_data;
            public int line_stride_in_bytes;
            public IntPtr p_metadata;
            public long timestamp;
        }

        private static IntPtr _dllHandle = IntPtr.Zero;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern IntPtr LoadLibrary(string lpFileName);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

        // Function delegates
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate bool NDIlib_initialize_fn();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void NDIlib_destroy_fn();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr NDIlib_send_create_fn(ref NDIlib_send_create_t p_create_settings);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void NDIlib_send_destroy_fn(IntPtr p_instance);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void NDIlib_send_send_video_v2_fn(IntPtr p_instance, ref NDIlib_video_frame_v2_t p_video_data);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int NDIlib_send_get_no_connections_fn(IntPtr p_instance, int timeout_ms);

        private static NDIlib_initialize_fn? _initialize;
        private static NDIlib_destroy_fn? _destroy;
        private static NDIlib_send_create_fn? _send_create;
        private static NDIlib_send_destroy_fn? _send_destroy;
        private static NDIlib_send_send_video_v2_fn? _send_send_video_v2;
        private static NDIlib_send_get_no_connections_fn? _send_get_no_connections;

        public static bool IsLoaded => _dllHandle != IntPtr.Zero;

        public static bool InitializeLibrary(out string statusMessage)
        {
            string[] searchPaths = new[]
            {
                Path.Combine(AppContext.BaseDirectory, "Processing.NDI.Lib.x64.dll"),
                Environment.GetEnvironmentVariable("NDI_RUNTIME_DIR_V6") != null ? Path.Combine(Environment.GetEnvironmentVariable("NDI_RUNTIME_DIR_V6")!, "Processing.NDI.Lib.x64.dll") : "",
                Environment.GetEnvironmentVariable("NDI_RUNTIME_DIR_V5") != null ? Path.Combine(Environment.GetEnvironmentVariable("NDI_RUNTIME_DIR_V5")!, "Processing.NDI.Lib.x64.dll") : "",
                @"C:\Program Files\NDI\NDI 6 Runtime\v6\Processing.NDI.Lib.x64.dll",
                @"C:\Program Files\NDI\NDI 5 Runtime\v5\Processing.NDI.Lib.x64.dll",
                "Processing.NDI.Lib.x64.dll"
            };

            foreach (var path in searchPaths)
            {
                if (!string.IsNullOrWhiteSpace(path) && (File.Exists(path) || path == "Processing.NDI.Lib.x64.dll"))
                {
                    _dllHandle = LoadLibrary(path);
                    if (_dllHandle != IntPtr.Zero)
                    {
                        statusMessage = $"Loaded NDI runtime from: {path}";
                        BindMethods();
                        return _initialize != null && _initialize();
                    }
                }
            }

            statusMessage = "NDI runtime DLL (Processing.NDI.Lib.x64.dll) not found. Please install NDI 6 Runtime or NDI Tools.";
            return false;
        }

        private static void BindMethods()
        {
            if (_dllHandle == IntPtr.Zero) return;

            _initialize = GetDelegate<NDIlib_initialize_fn>("NDIlib_initialize");
            _destroy = GetDelegate<NDIlib_destroy_fn>("NDIlib_destroy");
            _send_create = GetDelegate<NDIlib_send_create_fn>("NDIlib_send_create");
            _send_destroy = GetDelegate<NDIlib_send_destroy_fn>("NDIlib_send_destroy");
            _send_send_video_v2 = GetDelegate<NDIlib_send_send_video_v2_fn>("NDIlib_send_send_video_v2");
            _send_get_no_connections = GetDelegate<NDIlib_send_get_no_connections_fn>("NDIlib_send_get_no_connections");
        }

        private static T? GetDelegate<T>(string name) where T : Delegate
        {
            IntPtr proc = GetProcAddress(_dllHandle, name);
            if (proc == IntPtr.Zero) return null;
            return Marshal.GetDelegateForFunctionPointer<T>(proc);
        }

        public static IntPtr CreateSender(string streamName)
        {
            if (_send_create == null) return IntPtr.Zero;
            var settings = new NDIlib_send_create_t
            {
                p_ndi_name = streamName,
                clock_video = true,
                clock_audio = false
            };
            return _send_create(ref settings);
        }

        public static void DestroySender(IntPtr sender)
        {
            _send_destroy?.Invoke(sender);
        }

        public static void SendVideoFrame(IntPtr sender, ref NDIlib_video_frame_v2_t frame)
        {
            _send_send_video_v2?.Invoke(sender, ref frame);
        }

        public static int GetConnectionsCount(IntPtr sender)
        {
            return _send_get_no_connections?.Invoke(sender, 0) ?? 0;
        }

        public static void Cleanup()
        {
            _destroy?.Invoke();
        }
    }
}
