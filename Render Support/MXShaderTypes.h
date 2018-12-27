//
//  MXShaderTypes.h
//  Metal
//
//  Created by William Woody on 12/27/18.
//  Copyright © 2018 Glenview Software. All rights reserved.
//

#ifndef MXShaderTypes_h
#define MXShaderTypes_h

#include <simd/simd.h>

/*
 *	Buffer index values. We use an enumeration to declare the values, and
 *	do it in a way which can be shared between the .metal and the .m files
 *	so we don't accidentally get the indexes mismatched.
 */

typedef enum MXVertexIndex
{
	MXVertexIndexVertices = 0,		/* For [[stage_in]], the vertex buffer MUST BE 0 */
} MXVertexIndex;

/*
 *	Attribute indexes. This is the same idea as above, but for attributes.
 */

typedef enum MXAttributeIndex
{
	MXAttributeIndexPosition = 0,
	MXAttributeIndexColor = 1
} MXAttributeIndex;

#endif /* MXShaderTypes_h */
