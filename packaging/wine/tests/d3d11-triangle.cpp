// Minimal Direct3D 11 test: clears to blue and draws a rotating coloured triangle.
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <math.h>

static FILE *gLog;
#define LOG(...) do { fprintf(gLog, __VA_ARGS__); fflush(gLog); } while (0)

static int gResizeW, gResizeH, gW = 800, gH = 600, gDoResize = 1;
static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    if (m == WM_SIZE && w != SIZE_MINIMIZED) { gResizeW = LOWORD(l); gResizeH = HIWORD(l); }
    return DefWindowProcA(h, m, w, l);
}

static const char *kShader =
    "struct V { float4 p : SV_Position; float4 c : COLOR; };\n"
    "V vs(float2 p : POSITION, float4 c : COLOR) { V o; o.p = float4(p, 0, 1); o.c = c; return o; }\n"
    "float4 ps(V i) : SV_Target { return i.c; }\n";

struct Vertex { float x, y; float r, g, b, a; };

int WINAPI WinMain(HINSTANCE inst, HINSTANCE, LPSTR cmd, int) {
    gLog = fopen("C:\\tri.log", "w");
    int x = -1700, y = -450, seconds = 20;
    sscanf(cmd, "%d %d %d %d", &x, &y, &seconds, &gDoResize);

    WNDCLASSA wc = {};
    wc.lpfnWndProc = WndProc; wc.hInstance = inst; wc.lpszClassName = "DormerTri";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassA(&wc);
    HWND hwnd = CreateWindowA("DormerTri", "Dormer D3D11 test", WS_OVERLAPPEDWINDOW,
                              x, y, 800, 600, NULL, NULL, inst, NULL);
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    RECT wr; GetWindowRect(hwnd, &wr);
    LOG("window rect %ld,%ld %ld,%ld\n", wr.left, wr.top, wr.right, wr.bottom);

    gResizeW = gResizeH = 0;
    DXGI_SWAP_CHAIN_DESC sd = {};
    sd.BufferCount = 2;
    sd.BufferDesc.Width = 800; sd.BufferDesc.Height = 600;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd; sd.SampleDesc.Count = 1; sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL; IDXGISwapChain *sc = NULL;
    D3D_FEATURE_LEVEL want[] = { D3D_FEATURE_LEVEL_11_0 }, got;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, want, 1,
                                               D3D11_SDK_VERSION, &sd, &sc, &dev, &got, &ctx);
    LOG("CreateDeviceAndSwapChain hr=0x%08lx level=0x%x\n", (unsigned long)hr, hr == S_OK ? got : 0);
    if (FAILED(hr)) return 1;

    ID3D11Texture2D *bb = NULL; ID3D11RenderTargetView *rtv = NULL;
    hr = sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&bb);
    LOG("GetBuffer hr=0x%08lx\n", (unsigned long)hr);
    hr = dev->CreateRenderTargetView(bb, NULL, &rtv);
    LOG("CreateRenderTargetView hr=0x%08lx\n", (unsigned long)hr);

    ID3DBlob *vsb = NULL, *psb = NULL, *err = NULL;
    ID3D11VertexShader *vs = NULL; ID3D11PixelShader *ps = NULL; ID3D11InputLayout *il = NULL;
    ID3D11Buffer *vb = NULL;
    bool tri = false;
    hr = D3DCompile(kShader, strlen(kShader), "tri", NULL, NULL, "vs", "vs_4_0", 0, 0, &vsb, &err);
    LOG("D3DCompile vs hr=0x%08lx %s\n", (unsigned long)hr, err ? (char *)err->GetBufferPointer() : "");
    if (SUCCEEDED(hr)) {
        hr = D3DCompile(kShader, strlen(kShader), "tri", NULL, NULL, "ps", "ps_4_0", 0, 0, &psb, &err);
        LOG("D3DCompile ps hr=0x%08lx\n", (unsigned long)hr);
    }
    if (SUCCEEDED(hr)) {
        HRESULT a = dev->CreateVertexShader(vsb->GetBufferPointer(), vsb->GetBufferSize(), NULL, &vs);
        HRESULT b = dev->CreatePixelShader(psb->GetBufferPointer(), psb->GetBufferSize(), NULL, &ps);
        D3D11_INPUT_ELEMENT_DESC ied[] = {
            { "POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0 },
            { "COLOR", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 8, D3D11_INPUT_PER_VERTEX_DATA, 0 },
        };
        HRESULT c = dev->CreateInputLayout(ied, 2, vsb->GetBufferPointer(), vsb->GetBufferSize(), &il);
        D3D11_BUFFER_DESC bd = {};
        bd.ByteWidth = sizeof(Vertex) * 3; bd.Usage = D3D11_USAGE_DYNAMIC;
        bd.BindFlags = D3D11_BIND_VERTEX_BUFFER; bd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
        HRESULT d = dev->CreateBuffer(&bd, NULL, &vb);
        LOG("shaders vs=0x%08lx ps=0x%08lx layout=0x%08lx vb=0x%08lx\n",
            (unsigned long)a, (unsigned long)b, (unsigned long)c, (unsigned long)d);
        tri = SUCCEEDED(a) && SUCCEEDED(b) && SUCCEEDED(c) && SUCCEEDED(d);
    }

    DWORD start = GetTickCount(); unsigned frames = 0; HRESULT lastPresent = S_OK;
    for (;;) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) goto done;
            TranslateMessage(&msg); DispatchMessageA(&msg);
        }
        float t = (GetTickCount() - start) / 1000.0f;
        if (t > seconds) break;
        if (gResizeW && gResizeH && gDoResize) {
            ctx->OMSetRenderTargets(0, NULL, NULL);
            rtv->Release(); bb->Release();
            HRESULT r1 = sc->ResizeBuffers(0, gResizeW, gResizeH, DXGI_FORMAT_UNKNOWN, 0);
            HRESULT r2 = sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&bb);
            HRESULT r3 = dev->CreateRenderTargetView(bb, NULL, &rtv);
            LOG("resize to %dx%d: ResizeBuffers=0x%08lx GetBuffer=0x%08lx RTV=0x%08lx\n", gResizeW, gResizeH,
                (unsigned long)r1, (unsigned long)r2, (unsigned long)r3);
            gW = gResizeW; gH = gResizeH; gResizeW = gResizeH = 0;
        }
        float clear[4] = { 0.05f, 0.15f, 0.45f, 1.0f };
        ctx->OMSetRenderTargets(1, &rtv, NULL);
        ctx->ClearRenderTargetView(rtv, clear);
        if (tri) {
            D3D11_MAPPED_SUBRESOURCE ms;
            if (SUCCEEDED(ctx->Map(vb, 0, D3D11_MAP_WRITE_DISCARD, 0, &ms))) {
                Vertex *v = (Vertex *)ms.pData;
                for (int i = 0; i < 3; i++) {
                    float a = t + i * 2.0943951f;
                    v[i].x = 0.6f * sinf(a) * 0.75f; v[i].y = 0.6f * cosf(a);
                    v[i].r = i == 0; v[i].g = i == 1; v[i].b = i == 2; v[i].a = 1;
                }
                ctx->Unmap(vb, 0);
            }
            D3D11_VIEWPORT vp = { 0, 0, (float)gW, (float)gH, 0, 1 };
            UINT stride = sizeof(Vertex), off = 0;
            ctx->RSSetViewports(1, &vp);
            ctx->IASetInputLayout(il);
            ctx->IASetVertexBuffers(0, 1, &vb, &stride, &off);
            ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            ctx->VSSetShader(vs, NULL, 0);
            ctx->PSSetShader(ps, NULL, 0);
            ctx->Draw(3, 0);
        }
        lastPresent = sc->Present(1, 0);
        if (frames == 0) LOG("first Present hr=0x%08lx\n", (unsigned long)lastPresent);
        frames++;
    }
done:
    LOG("frames=%u in %lu ms, last Present hr=0x%08lx, triangle=%d\n",
        frames, (unsigned long)(GetTickCount() - start), (unsigned long)lastPresent, tri);
    fclose(gLog);
    return 0;
}
