using System;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Threading;

namespace BackgroundEngine.Ndi
{
    class Program
    {
        const int WIDTH = 1920;
        const int HEIGHT = 1080;
        const int STRIDE = WIDTH * 4;
        const int FRAME_SIZE = STRIDE * HEIGHT; // 8,294,400 bytes
        const string DEFAULT_STREAM_NAME = "BackgroundEngine-PGM";
        const string PIPE_NAME = "BackgroundEngine_NdiPipe";

        static void Main(string[] args)
        {
            Console.OutputEncoding = System.Text.Encoding.UTF8;
            string streamName = DEFAULT_STREAM_NAME;

            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--stream" && i + 1 < args.Length)
                {
                    streamName = args[i + 1];
                }
            }

            Console.WriteLine($"{{\"type\":\"init\",\"stream\":\"{streamName}\",\"resolution\":\"{WIDTH}x{HEIGHT}\",\"fps\":60}}");

            bool ndiOk = NdiWrapper.InitializeLibrary(out string statusMsg);
            Console.WriteLine($"{{\"type\":\"runtime\",\"loaded\":{ndiOk.ToString().ToLower()},\"message\":\"{statusMsg.Replace("\\", "\\\\")}\"}}");

            IntPtr sender = IntPtr.Zero;
            if (ndiOk)
            {
                sender = NdiWrapper.CreateSender(streamName);
                if (sender != IntPtr.Zero)
                {
                    Console.WriteLine($"{{\"type\":\"status\",\"state\":\"READY\",\"stream\":\"{streamName}\"}}");
                }
                else
                {
                    Console.WriteLine("{\"type\":\"status\",\"state\":\"FAILED\",\"error\":\"Failed to create NDI sender\"}");
                }
            }
            else
            {
                Console.WriteLine("{\"type\":\"status\",\"state\":\"FALLBACK_ACTIVE\",\"warning\":\"NDI Runtime not installed. CEF/HTTP output fallback is active.\"}");
            }

            byte[] localBuffer = new byte[FRAME_SIZE];
            GCHandle pinnedBuffer = GCHandle.Alloc(localBuffer, GCHandleType.Pinned);
            IntPtr bufferPtr = pinnedBuffer.AddrOfPinnedObject();

            var videoFrame = new NdiWrapper.NDIlib_video_frame_v2_t
            {
                xres = WIDTH,
                yres = HEIGHT,
                FourCC = NdiWrapper.NDIlib_FourCC_video_type_e.NDIlib_FourCC_video_type_BGRA,
                frame_rate_N = 60000,
                frame_rate_D = 1000,
                picture_aspect_ratio = 16.0f / 9.0f,
                frame_format_type = NdiWrapper.NDIlib_frame_format_type_e.NDIlib_frame_format_type_progressive,
                line_stride_in_bytes = STRIDE,
                p_data = bufferPtr,
                timecode = 0,
                timestamp = 0
            };

            bool running = true;
            Console.CancelKeyPress += (s, e) =>
            {
                e.Cancel = true;
                running = false;
            };

            long framesSent = 0;
            long lastStatsTime = Environment.TickCount64;

            // Start Named Pipe listener thread for direct zero-copy node.js pipe transmission
            var pipeThread = new Thread(() =>
            {
                while (running)
                {
                    try
                    {
                        using var pipeServer = new NamedPipeServerStream(
                            PIPE_NAME,
                            PipeDirection.In,
                            1,
                            PipeTransmissionMode.Byte,
                            PipeOptions.Asynchronous,
                            FRAME_SIZE * 4,
                            0);

                        Console.WriteLine("{\"type\":\"pipe_waiting\"}");
                        pipeServer.WaitForConnection();
                        Console.WriteLine("{\"type\":\"pipe_connected\"}");

                        int offset = 0;
                        byte[] readChunk = new byte[65536];

                        while (running && pipeServer.IsConnected)
                        {
                            int bytesRead = pipeServer.Read(localBuffer, offset, FRAME_SIZE - offset);
                            if (bytesRead <= 0) break;
                            offset += bytesRead;

                            if (offset >= FRAME_SIZE)
                            {
                                offset = 0;
                                if (sender != IntPtr.Zero)
                                {
                                    NdiWrapper.SendVideoFrame(sender, ref videoFrame);
                                    framesSent++;
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        if (running)
                        {
                            Console.WriteLine($"{{\"type\":\"pipe_error\",\"error\":\"{ex.Message.Replace("\\", "\\\\")}\"}}");
                            Thread.Sleep(500);
                        }
                    }
                }
            })
            { IsBackground = true };
            pipeThread.Start();

            try
            {
                while (running)
                {
                    Thread.Sleep(1000);
                    long now = Environment.TickCount64;
                    int receivers = sender != IntPtr.Zero ? NdiWrapper.GetConnectionsCount(sender) : 0;
                    long elapsed = now - lastStatsTime;
                    double actualFps = (framesSent * 1000.0) / Math.Max(1, elapsed);

                    Console.WriteLine($"{{\"type\":\"telemetry\",\"fps\":{actualFps:F1},\"frames\":{framesSent},\"receivers\":{receivers},\"ndiLoaded\":{ndiOk.ToString().ToLower()}}}");

                    framesSent = 0;
                    lastStatsTime = now;
                }
            }
            finally
            {
                running = false;
                if (pinnedBuffer.IsAllocated) pinnedBuffer.Free();

                if (sender != IntPtr.Zero)
                {
                    NdiWrapper.DestroySender(sender);
                }
                NdiWrapper.Cleanup();

                Console.WriteLine("{\"type\":\"status\",\"state\":\"STOPPED\"}");
            }
        }
    }
}
