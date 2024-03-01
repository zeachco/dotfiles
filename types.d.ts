declare module "bun" {
  export function $(strings: TemplateStringsArray, ...values: any[]): Promise<string>;
}
