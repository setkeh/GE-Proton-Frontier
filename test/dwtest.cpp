// Minimal DirectWrite probe: load a font file as a custom font set, enumerate names,
// create a face, fetch glyph indices and metrics. Prints a step marker before each call.
#define COBJMACROS
#include <windows.h>
#include <dwrite_3.h>
#include <stdio.h>
#include <wchar.h>
#define STEP(x) do { fprintf(stderr, "[step] %s\n", x); fflush(stderr); } while (0)
static void names(IDWriteLocalizedStrings *ls, const char *label) {
    if (!ls) { fprintf(stderr, "  %s: (null)\n", label); return; }
    UINT32 n = ls->GetCount();
    for (UINT32 i = 0; i < n; i++) { WCHAR buf[256] = {0}; ls->GetString(i, buf, 256); fprintf(stderr, "  %s[%u] = \"%ls\" (len %zu)\n", label, i, buf, wcslen(buf)); }
}
int wmain(int argc, wchar_t **argv) {
    freopen("dwtest.log", "w", stderr); setvbuf(stderr, NULL, _IONBF, 0);
    if (argc < 2) { fprintf(stderr, "usage: dwtest <font.ttf>\n"); return 2; }
    IDWriteFactory5 *f = NULL;
    STEP("DWriteCreateFactory");
    if (FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED, __uuidof(IDWriteFactory5), (IUnknown**)&f))) { fprintf(stderr, "no factory\n"); return 1; }
    IDWriteFontFile *file = NULL; STEP("CreateFontFileReference");
    if (FAILED(f->CreateFontFileReference(argv[1], NULL, &file))) { fprintf(stderr, "no file ref\n"); return 1; }
    IDWriteFontSetBuilder1 *b = NULL; STEP("CreateFontSetBuilder"); f->CreateFontSetBuilder(&b);
    STEP("AddFontFile"); HRESULT hr = b->AddFontFile(file); fprintf(stderr, "  AddFontFile hr=%08lx\n", hr);
    IDWriteFontSet *set = NULL; STEP("CreateFontSet"); b->CreateFontSet(&set);
    fprintf(stderr, "  fontset count=%u\n", set ? set->GetFontCount() : 0);
    IDWriteFontCollection1 *coll = NULL; STEP("CreateFontCollectionFromFontSet"); f->CreateFontCollectionFromFontSet(set, &coll);
    UINT32 fam = coll ? coll->GetFontFamilyCount() : 0; fprintf(stderr, "  families=%u\n", fam);
    for (UINT32 i = 0; i < fam; i++) {
        IDWriteFontFamily1 *family = NULL; STEP("GetFontFamily"); coll->GetFontFamily(i, &family);
        IDWriteLocalizedStrings *fn = NULL; STEP("GetFamilyNames"); family->GetFamilyNames(&fn); names(fn, "family");
        UINT32 fc = family->GetFontCount(); fprintf(stderr, "  fonts in family=%u\n", fc);
        for (UINT32 j = 0; j < fc; j++) {
            IDWriteFont3 *font = NULL; STEP("GetFont"); family->GetFont(j, &font);
            IDWriteLocalizedStrings *face = NULL; STEP("GetFaceNames"); font->GetFaceNames(&face); names(face, "face");
            fprintf(stderr, "  weight=%d stretch=%d style=%d\n", font->GetWeight(), font->GetStretch(), font->GetStyle());
            BOOL exists = FALSE; IDWriteLocalizedStrings *full = NULL; STEP("GetInformationalStrings(FULL_NAME)"); font->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_FULL_NAME, &full, &exists); names(full, "fullname");
            IDWriteFontFace3 *ff = NULL; STEP("CreateFontFace"); hr = font->CreateFontFace(&ff); fprintf(stderr, "  CreateFontFace hr=%08lx\n", hr);
            if (ff) { UINT32 cps[3] = {'A','a','0'}; UINT16 gi[3]; STEP("GetGlyphIndices"); ff->GetGlyphIndices(cps, 3, gi); fprintf(stderr, "  glyphs A a 0 = %u %u %u\n", gi[0], gi[1], gi[2]);
                DWRITE_FONT_METRICS1 m; STEP("GetMetrics"); ff->GetMetrics(&m); fprintf(stderr, "  upem=%u ascent=%u\n", m.designUnitsPerEm, m.ascent);
                DWRITE_GLYPH_METRICS gm[3]; STEP("GetDesignGlyphMetrics"); ff->GetDesignGlyphMetrics(gi, 3, gm, FALSE); fprintf(stderr, "  advA=%d\n", gm[0].advanceWidth); }
        }
    }
    // Also the old-style path some apps use: CreateFontFace directly from the file.
    IDWriteFontFace *ff0 = NULL; STEP("Factory::CreateFontFace(file)"); hr = f->CreateFontFace(DWRITE_FONT_FACE_TYPE_TRUETYPE, 1, &file, 0, DWRITE_FONT_SIMULATIONS_NONE, &ff0); fprintf(stderr, "  hr=%08lx\n", hr);
    STEP("done"); return 0;
}
