/*
 * Copyright (c) 2013 Matthew Stevens
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <gtest/gtest.h>

using testing::TestCase;
using testing::TestInfo;
using testing::TestPartResult;
using testing::UnitTest;

/**
 * A Google Test listener that reports failures to XCTest.
 */
class XCTestListener : public testing::EmptyTestEventListener {
public:
    XCTestListener(XCTestCase *testCase) :
        _testCase(testCase) {}

    void OnTestPartResult(const TestPartResult& test_part_result) {
        if (test_part_result.passed())
            return;

        int lineNumber = test_part_result.line_number();
        NSString *path = [@(test_part_result.file_name()) stringByStandardizingPath];
        NSString *description = @(test_part_result.message());
        [_testCase recordFailureWithDescription:description
                                         inFile:path
                                         atLine:(lineNumber >= 0 ? (NSUInteger)lineNumber : 0)
                                       expected:YES];
    }

private:
    XCTestCase *_testCase;
};

/**
 * Test suite used to run Google Test cases.
 *
 * This test suite skips its own run and instead runs each of its sub-tests. This results
 * in the Google Test cases being reported at the same level as other XCTest cases.
 *
 * Additionally, if a test case has been completely filtered out it is not run at all.
 * This eliminates noise from the test report when running only a subset of tests.
 */
@interface GoogleTestSuite : XCTestSuite
@end

@implementation GoogleTestSuite

- (void)performTest:(XCTestSuiteRun *)testRun {
    for (XCTest *test in self.tests) {
        if (test.testCaseCount > 0) {
            [testRun addTestRun:[test run]];
        }
    }
}

@end

/**
 * A test case that executes Google Test, reporting test results to XCTest.
 *
 * XCTest loads tests by looking for all classes derived from XCTestCase and calling
 * +defaultTestSuite on each of them. Normally this method returns an XCTestSuite
 * containing an XCTestCase for each method of the receiver whose name begins with "test".
 * Instead this class returns a custom test suite that runs an XCTestSuite for each Google
 * Test case.
 */
@interface GoogleTests : XCTestCase
@end

@implementation GoogleTests {
    NSString *_name;
    NSString *_className;
    NSString *_methodName;
    NSString *_googleTestFilter;
}

- (id)initWithClassName:(NSString *)className methodName:(NSString *)methodName testFilter:(NSString *)filter {
    self = [super initWithSelector:@selector(runTest)];
    if (self) {
        _className = [className copy];
        _methodName = [methodName copy];
        _name = [NSString stringWithFormat:@"-[%@ %@]", _className, _methodName];
        _googleTestFilter = [filter copy];
    }
    return self;
}

- (NSString *)name {
    return _name;
}

/**
 * Returns the class name reported to Xcode for this test.
 */
- (NSString *)testClassName {
    return _className;
}

/**
 * Returns the method name reported to Xcode for this test.
 */
- (NSString *)testMethodName {
    return _methodName;
}

+ (id)defaultTestSuite {
    // Pass the command-line arguments to Google Test to support the --gtest options
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];

    int i = 0;
    int argc = (int)[arguments count];
    const char **argv = (const char **)calloc((unsigned int)argc + 1, sizeof(const char *));
    for (NSString *arg in arguments) {
        argv[i++] = [arg UTF8String];
    }

    testing::InitGoogleTest(&argc, (char **)argv);
    UnitTest *googleTest = UnitTest::GetInstance();
    testing::TestEventListeners& listeners = googleTest->listeners();
    delete listeners.Release(listeners.default_result_printer());
    free(argv);

    XCTestSuite *testSuite = [GoogleTestSuite testSuiteWithName:NSStringFromClass([self class])];

    for (int testCaseIndex = 0; testCaseIndex < googleTest->total_test_case_count(); testCaseIndex++) {
        const TestCase *testCase = googleTest->GetTestCase(testCaseIndex);
        NSString *testCaseName = @(testCase->name());

        // For typed tests Google Test uses '/' to separate the parts of the test case
        // name. This is incompatible with Xcode's parsing and causes these tests not to
        // appear in the UI propertly. Replace these characters in the class name reported
        // to Xcode.
        NSString *className = [testCaseName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

        XCTestSuite *testCaseSuite = [XCTestSuite testSuiteWithName:className];

        for (int testIndex = 0; testIndex < testCase->total_test_count(); testIndex++) {
            const TestInfo *testInfo = testCase->GetTestInfo(testIndex);
            NSString *testName = @(testInfo->name());
            NSString *testFilter = [NSString stringWithFormat:@"%@.%@", testCaseName, testName];

            [testCaseSuite addTest:[[self alloc] initWithClassName:className
                                                        methodName:testName
                                                        testFilter:testFilter]];
        }

        [testSuite addTest:testCaseSuite];
    }

    return testSuite;
}

/**
 * Runs a single test.
 */
- (void)runTest {
    XCTestListener *listener = new XCTestListener(self);
    UnitTest *googleTest = UnitTest::GetInstance();
    googleTest->listeners().Append(listener);

    testing::GTEST_FLAG(filter) = [_googleTestFilter UTF8String];

    (void)RUN_ALL_TESTS();

    delete googleTest->listeners().Release(listener);

    int totalTestsRun = googleTest->successful_test_count() + googleTest->failed_test_count();
    XCTAssertEqual(totalTestsRun, 1, @"Expected to run a single test for filter \"%@\"", _googleTestFilter);
}

@end
