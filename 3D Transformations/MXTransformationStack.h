//
//  MXTransformationStack.h
//  MetalTest
//
//  Created by William Woody on 12/24/18.
//  Copyright © 2018 Glenview Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>

/****************************************************************************/
/*																			*/
/*	Constants																*/
/*																			*/
/****************************************************************************/

typedef enum MTXAxis
{
	MTXXAxis = 1,
	MTXYAxis,
	MTXZAxis
} MTXAxis;

/****************************************************************************/
/*																			*/
/*	Class Declarations														*/
/*																			*/
/****************************************************************************/

@interface MXTransformationStack : NSObject

- (void)push;
- (void)pop;
- (void)clear;

- (void)identity;			// Set CTM to identity
- (void)translateByX:(float)x y:(float)y z:(float)z;	// add translate
- (void)scaleByX:(float)x y:(float)y z:(float)z;		// add scale
- (void)scaleBy:(float)s;
- (void)rotateAroundAxis:(vector_float3)axis byAngle:(float)s; // add rotate
- (void)rotateAroundFixedAxis:(MTXAxis)axis byAngle:(float)s;

// perspective
- (void)perspective:(float)fov aspect:(float)aspect near:(float)n far:(float)f;
- (void)perspective:(float)fov aspect:(float)aspect near:(float)n;

/*
 *	Current transformation matrix
 */

- (matrix_float4x4)ctm;
- (matrix_float4x4)inverseCtm;

@end

