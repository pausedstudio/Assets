//
//  CoreSVG.h
//  AssetCatalogKit
//
//  Private CoreSVG symbols for vector asset rendering
//

#ifndef CoreSVG_h
#define CoreSVG_h

#import <CoreGraphics/CoreGraphics.h>

struct CGSVGDocument;
typedef struct CGSVGDocument *CGSVGDocumentRef;

// Weak imports - these symbols may not be available on all systems
int CGSVGDocumentWriteToData(CGSVGDocumentRef, CFDataRef, CFDictionaryRef) __attribute__((weak_import));
void CGContextDrawSVGDocument(CGContextRef, CGSVGDocumentRef) __attribute__((weak_import));
CGSize CGSVGDocumentGetCanvasSize(CGSVGDocumentRef) __attribute__((weak_import));

#endif /* CoreSVG_h */
