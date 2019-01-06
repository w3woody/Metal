//
//  MXTransformationStack.m
//  MetalTest
//
//  Created by William Woody on 12/24/18.
//  Copyright © 2018 Glenview Software. All rights reserved.
//

#import "MXTransformationStack.h"

@interface MXTransformationStack ()
{
	matrix_float4x4 ctm;

	uint16_t size;
	uint16_t pos;
	matrix_float4x4 *stack;
}
@end

/****************************************************************************/
/*																			*/
/*	Construction/Destruction												*/
/*																			*/
/****************************************************************************/

@implementation MXTransformationStack

- (instancetype)init
{
	if (nil != (self = [super init])) {
		[self identity];

		size = 16;
		pos = 0;
		stack = (matrix_float4x4 *)malloc(sizeof(matrix_float4x4) * size);
	}
	return self;
}

- (void)dealloc
{
	if (stack) free(stack);
}

/****************************************************************************/
/*																			*/
/*	Stack																	*/
/*																			*/
/****************************************************************************/

- (void)push
{
	if (pos >= size) {
		/*
		 *	Grow stack
		 */

		uint16_t newSize = (size * 4) / 3;
		matrix_float4x4 *tmp = realloc(stack, newSize * sizeof(matrix_float4x4));
		if (tmp == NULL) return;

		stack = tmp;
		size = newSize;
	}

	stack[pos++] = ctm;
}

- (void)pop
{
	if (pos > 0) {
		ctm = stack[--pos];
	}
}

- (void)clear
{
	[self identity];
	pos = 0;
}

/****************************************************************************/
/*																			*/
/*	Matrix manpulation														*/
/*																			*/
/****************************************************************************/

static void MTXIdentity(matrix_float4x4 *ref)
{
	memset(ref,0,sizeof(matrix_float4x4));
	for (int i = 0; i < 4; ++i) ref->columns[i][i] = 1;
}

- (void)identity
{
	MTXIdentity(&ctm);
}

- (void)translateByX:(float)x y:(float)y z:(float)z
{
	matrix_float4x4 m;

	MTXIdentity(&m);
	m.columns[3][0] = x;
	m.columns[3][1] = y;
	m.columns[3][2] = z;

	ctm = simd_mul(ctm, m);
}

- (void)scaleByX:(float)x y:(float)y z:(float)z
{
	matrix_float4x4 m;

	MTXIdentity(&m);
	m.columns[0][0] = x;
	m.columns[1][1] = y;
	m.columns[2][2] = z;

	ctm = simd_mul(ctm, m);
}

- (void)scaleBy:(float)s
{
	matrix_float4x4 m;

	MTXIdentity(&m);
	m.columns[0][0] = s;
	m.columns[1][1] = s;
	m.columns[2][2] = s;

	ctm = simd_mul(ctm, m);
}

- (void)rotateAroundAxis:(vector_float3)axis byAngle:(float)angle
{
	matrix_float4x4 m;

	float x = axis[0];
	float y = axis[1];
	float z = axis[2];
	float c = cosf(angle);
	float s = sinf(angle);
	float t = 1 - c;

	m.columns[0][0] = t * x * x + c;
	m.columns[0][1] = t * x * y + z * s;
	m.columns[0][2] = t * x * z - y * s;
	m.columns[0][3] = 0;

	m.columns[1][0] = t * x * y - z * s;
	m.columns[1][1] = t * y * y + c;
	m.columns[1][2] = t * y * z + x * s;
	m.columns[1][3] = 0;

	m.columns[2][0] = t * x * z + y * s;
	m.columns[2][1] = t * y * z - x * s;
	m.columns[2][2] = t * z * z + c;
	m.columns[2][3] = 0;

	m.columns[3][0] = 0;
	m.columns[3][1] = 0;
	m.columns[3][2] = 0;
	m.columns[3][3] = 1;

	ctm = simd_mul(ctm, m);
}

- (void)rotateAroundFixedAxis:(MTXAxis)axis byAngle:(float)angle
{
	matrix_float4x4 m;
	MTXIdentity(&m);

	float c = cosf(angle);
	float s = sinf(angle);

	switch (axis) {
		case MTXXAxis:
			m.columns[1][1] = c;
			m.columns[2][2] = c;
			m.columns[2][1] = -s;
			m.columns[1][2] = s;
			break;
		case MTXYAxis:
			m.columns[0][0] = c;
			m.columns[2][2] = c;
			m.columns[2][0] = s;
			m.columns[0][2] = -s;
			break;
		case MTXZAxis:
			m.columns[0][0] = c;
			m.columns[1][1] = c;
			m.columns[1][0] = s;
			m.columns[0][1] = -s;
			break;
	}

	ctm = simd_mul(ctm, m);
}

// perspective
- (void)perspective:(float)fov aspect:(float)aspect near:(float)n far:(float)f
{
	matrix_float4x4 m;
	memset(&m,0,sizeof(matrix_float4x4));

	m.columns[0][0] = fov/aspect;
	m.columns[1][1] = fov;
	m.columns[2][2] = (f+n)/(n-f);
	m.columns[2][3] = -1;
	m.columns[3][2] = (2 * n * f)/(n - f);

	ctm = simd_mul(ctm, m);
}


- (void)perspective:(float)fov aspect:(float)aspect near:(float)n
{
	matrix_float4x4 m;
	memset(&m,0,sizeof(matrix_float4x4));

	m.columns[0][0] = fov/aspect;
	m.columns[1][1] = fov;
	m.columns[2][3] = -1;
	m.columns[3][2] = -n;

	ctm = simd_mul(ctm, m);
}

/*
 *	Current transformation matrix
 */

- (matrix_float4x4)ctm
{
	return ctm;
}

- (matrix_float4x4)inverseCtm
{
	return simd_inverse(ctm);
}

@end
