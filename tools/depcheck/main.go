// depcheck 执行 PLAN.md §0 / 风险 R11 的依赖白名单。
//
// 只允许 moonbitlang/* 与 moonbit-community/* 两个命名空间；官方成员的个人包
// 与其余第三方模块在进入提交之前就被拒绝。
//
// 为什么用 Go 而不是 MoonBit 脚本：这道闸门不能依赖被它守的 MoonBit 工具链
// （工具链坏过一次，闸门必须照跑），并且判定规则要能被单元测试锁住。Go 单文件 +
// 标准库 + go test 同时满足，也不引入任何包管理依赖树；本实现同时充当“对照实现”，
// 以后用别的语言重写都拿它的用例对拍。
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

// depsFromManifest 扫描 moon.mod，返回每个 import 块**顶层**的字符串。
//
// 这里不做按行匹配：`import` 与 `{` 可以分行，依赖也可以写成
// `"a/b": { path = "../b" }`。按行判断会被纯格式化绕过（评审 P2-1）。
// 扫描器跳过字符串与注释，找到 `import` 后进入块内按花括号深度取字符串：
// 深度 1 的字符串是模块名，深度 2 的 `path` 不进入白名单判定。
func depsFromManifest(src string) []string {
	var deps []string
	i := 0
	for i < len(src) {
		switch {
		case src[i] == '"':
			i = skipString(src, i)
		case src[i] == '#':
			i = skipLine(src, i)
		case src[i] == '/' && i+1 < len(src) && src[i+1] == '/':
			i = skipLine(src, i)
		case isWordAt(src, i, "import"):
			blockDeps, next := parseImportBlock(src, i+len("import"))
			deps = append(deps, blockDeps...)
			i = next
		default:
			i++
		}
	}
	return deps
}

// parseImportBlock 从 `import` 之后开始找 `{`，解析到匹配的 `}`。
// 如果 `import` 之后先出现别的记号（例如字符串里的单词），原样返回、不取依赖。
func parseImportBlock(src string, from int) ([]string, int) {
	i := from
	for i < len(src) && src[i] != '{' {
		switch {
		case src[i] == '#' || (src[i] == '/' && i+1 < len(src) && src[i+1] == '/'):
			i = skipLine(src, i)
		case isSpace(src[i]):
			i++
		default:
			return nil, i
		}
	}
	if i >= len(src) {
		return nil, i
	}

	var deps []string
	depth := 0
	for i < len(src) {
		switch {
		case src[i] == '"':
			end := skipString(src, i)
			if depth == 1 {
				deps = append(deps, src[i+1:end-1])
			}
			i = end
		case src[i] == '#' || (src[i] == '/' && i+1 < len(src) && src[i+1] == '/'):
			i = skipLine(src, i)
		case src[i] == '{':
			depth++
			i++
		case src[i] == '}':
			depth--
			i++
			if depth == 0 {
				return deps, i
			}
		default:
			i++
		}
	}
	return deps, i
}

// skipString 从开引号跳到闭引号之后，处理反斜杠转义。
func skipString(src string, i int) int {
	quote := src[i]
	i++
	for i < len(src) {
		switch src[i] {
		case '\\':
			i += 2
		case quote:
			return i + 1
		default:
			i++
		}
	}
	return i
}

// skipLine 跳到行尾之后。
func skipLine(src string, i int) int {
	for i < len(src) && src[i] != '\n' {
		i++
	}
	if i < len(src) {
		i++
	}
	return i
}

func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

// isWordAt 判断 i 处是否为独立单词 word（前后不是标识符字符）。
func isWordAt(src string, i int, word string) bool {
	if i+len(word) > len(src) || src[i:i+len(word)] != word {
		return false
	}
	if i > 0 && isIdentChar(src[i-1]) {
		return false
	}
	if i+len(word) < len(src) && isIdentChar(src[i+len(word)]) {
		return false
	}
	return true
}

func isIdentChar(c byte) bool {
	return c == '_' || c == '-' ||
		('0' <= c && c <= '9') || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
}

// modulePath 去掉可选的 "@version" 后缀。
func modulePath(dep string) string {
	if i := strings.IndexByte(dep, '@'); i >= 0 {
		return dep[:i]
	}
	return dep
}

// forbidden 返回两个允许命名空间之外的依赖。
func forbidden(deps []string) []string {
	var bad []string
	for _, dep := range deps {
		path := modulePath(dep)
		if strings.HasPrefix(path, "moonbitlang/") ||
			strings.HasPrefix(path, "moonbit-community/") {
			continue
		}
		bad = append(bad, dep)
	}
	return bad
}

func main() {
	flag.Parse()
	path := "moon.mod"
	if flag.NArg() > 0 {
		path = flag.Arg(0)
	}

	src, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "depcheck: %v\n", err)
		os.Exit(2)
	}

	deps := depsFromManifest(string(src))
	bad := forbidden(deps)
	for _, dep := range bad {
		fmt.Fprintf(os.Stderr,
			"depcheck: forbidden dependency %q (allowed: moonbitlang/*, moonbit-community/*)\n", dep)
	}
	if len(bad) > 0 {
		os.Exit(1)
	}
	fmt.Printf("depcheck: ok (%d dependencies)\n", len(deps))
}
