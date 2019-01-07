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
	MXVertexIndexUniforms = 1,		/* Location of uniforms */
} MXVertexIndex;

/*
 *	Fragment indexes
 */

typedef enum MXFragmentIndex
{
	MXFragmentIndexColor = 0,			/* Location of color vector */
} MXFragmentIndex;

/*
 *	Attribute indexes. This is the same idea as above, but for attributes.
 */

typedef enum MXAttributeIndex
{
	MXAttributeIndexPosition = 0,
	MXAttributeIndexNormal = 1,
	MXAttributeIndexTexture = 2,
} MXAttributeIndex;

/*
 *	Uniforms structure
 */

typedef struct MXUniforms
{
	matrix_float4x4 model;
	matrix_float4x4 view;
	matrix_float4x4 inverse;	// inverse of model
} MXUniforms;

typedef struct MXLayerCount
{
	unsigned short count;
} MXLayerCount;

#endif /* MXShaderTypes_h */
